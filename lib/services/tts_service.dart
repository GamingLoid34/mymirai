import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTtsSpeechRatePref = 'my_mirai_tts_speech_rate';

enum TtsPlayerState { idle, loading, playing, paused, error }

class TtsService extends ChangeNotifier {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  static bool _swedishWarningShownThisSession = false;

  final FlutterTts _tts = FlutterTts();

  TtsPlayerState _state = TtsPlayerState.idle;
  TtsPlayerState get state => _state;

  List<String> _sentences = [];
  List<String> get sentences => List.unmodifiable(_sentences);

  int _currentIndex = -1;
  int get currentSentenceIndex => _currentIndex;

  double _speechRate = 1.0;
  double get speechRate => _speechRate;

  bool _swedishMissingWarningShown = false;
  bool _initialized = false;
  bool _userInitiatedStop = false;
  Timer? _nextSentenceTimer;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Chunk I (vuxen): rapporter hela aktiva lyssningspass (sekunder) — satt av TTS-sheet.
  Future<void> Function(int seconds)? _listeningReporter;

  int _sessionListenedSecs = 0;
  DateTime? _playingWallStart;

  void setListeningReporter(Future<void> Function(int seconds)? reporter) {
    _listeningReporter = reporter;
    if (reporter == null) {
      _playingWallStart = null;
    }
  }

  /// Anropas när uppspelningen når slutet naturligt (inte vid manuellt stopp/paus).
  VoidCallback? onFinished;

  bool get _listeningOn => _listeningReporter != null;

  void _tickClosePlayingWall() {
    if (!_listeningOn || _playingWallStart == null) {
      _playingWallStart = null;
      return;
    }
    final secs = DateTime.now().difference(_playingWallStart!).inSeconds;
    if (secs > 0) {
      _sessionListenedSecs += secs;
    }
    _playingWallStart = null;
  }

  void _tickOpenPlayingWall() {
    if (!_listeningOn || _state != TtsPlayerState.playing) {
      return;
    }
    _playingWallStart ??= DateTime.now();
  }

  void _flushListeningReport() {
    if (!_listeningOn) {
      _sessionListenedSecs = 0;
      _playingWallStart = null;
      return;
    }
    _tickClosePlayingWall();
    final secs = _sessionListenedSecs;
    _sessionListenedSecs = 0;
    if (secs <= 0) {
      _playingWallStart = null;
      return;
    }
    final reporter = _listeningReporter!;
    reporter(secs)
        .then((_) => null)
        .catchError((Object e, StackTrace st) {
          debugPrint('[Tts] listening report failed: $e');
          return null;
        });
    _playingWallStart = null;
  }

  bool get shouldShowSwedishWarning =>
      _swedishMissingWarningShown &&
      !_swedishWarningShownThisSession &&
      _state == TtsPlayerState.playing;

  void markSwedishWarningShown() {
    _swedishWarningShownThisSession = true;
  }

  Future<void> _init() async {
    if (_initialized) return;
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getDouble(_kTtsSpeechRatePref);
        if (saved != null) {
          _speechRate = saved.clamp(0.75, 2.0);
        }
      } catch (_) {
        // Ogiltiga prefs eller plattformsfel — kör vidare med standard 1.0.
      }

      final available = await _tts.getLanguages;
      final hasSwedish = (available as List?)
              ?.any((l) => l.toString().toLowerCase().startsWith('sv')) ??
          false;

      if (hasSwedish) {
        await _tts.setLanguage('sv-SE');
      } else {
        await _tts.setLanguage('en-US');
        _swedishMissingWarningShown = true;
      }

      await _tts.setSpeechRate(_mappedRate(_speechRate));
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      // TODO(tts-web): completion-handler kan vara opålitlig på vissa browsers, se openissues om det fallerar.
      _tts.setCompletionHandler(() {
        debugPrint('[Tts] completion fired idx=$_currentIndex');
        _nextSentenceTimer?.cancel();
        _tickClosePlayingWall();
        _playNextSentence();
      });
      _tts.setErrorHandler((msg) {
        final text = msg.toString().toLowerCase();
        // Browser Speech API: "interrupted" och "canceled" är inga fel,
        // de triggas av vår egen .stop() vid skip/rate-byte.
        if (text.contains('interrupt') || text.contains('cancel')) {
          return;
        }
        _tickClosePlayingWall();
        _state = TtsPlayerState.error;
        _errorMessage = msg.toString();
        notifyListeners();
      });

      _initialized = true;
    } catch (_) {
      _state = TtsPlayerState.error;
      _errorMessage =
          'Din webbläsare stöder inte uppläsning. Prova Chrome eller mobilappen.';
      notifyListeners();
    }
  }

  double _mappedRate(double appRate) {
    if (kIsWeb) {
      // Browser Web Speech API: 1.0 = normal. App-skala 0.75–2.0 mappar 1:1.
      return appRate;
    }
    if (Platform.isAndroid) {
      // Android TTS engine: 0.5 = upplevd normal hastighet.
      // App-skala 0.75-2.0 -> 0.375-1.0.
      return (appRate * 0.5).clamp(0.1, 1.5);
    }
    // iOS: 1.0 = normal.
    return appRate;
  }

  Duration _estimateDuration(String text, double rate) {
    // Svenska: ~16 tecken/sekund vid app-rate 1.0 (efter rate-fix).
    final charsPerSecond = 16.0 * rate;
    final seconds = (text.length / charsPerSecond).clamp(2.0, 60.0);
    // Buffer 300ms - räcker för att undvika överlapp utan onödig dödtid.
    return Duration(milliseconds: ((seconds * 1000) + 300).toInt());
  }

  /// Delar upp text i meningar för uppläsning. Public + statisk för att vara
  /// testbar och för att VO-08 kan beräkna teckenoffset per mening mot
  /// samma split som faktiskt spelas upp.
  static List<String> splitSentences(String text) => _splitSentences(text);

  static List<String> _splitSentences(String text) {
    if (text.trim().isEmpty) return [];
    final raw = text
        .split(RegExp(r'(?<=[.!?])\s+|\n\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final merged = <String>[];
    for (final s in raw) {
      if (merged.isNotEmpty && s.length < 20) {
        merged[merged.length - 1] = '${merged.last} $s';
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  Future<void> loadAndPlay(String text) async {
    _flushListeningReport();
    _sessionListenedSecs = 0;
    _playingWallStart = null;

    _state = TtsPlayerState.loading;
    _errorMessage = null;
    notifyListeners();

    await _init();
    if (_state == TtsPlayerState.error) return;

    _sentences = _splitSentences(text);
    if (_sentences.isEmpty) {
      _state = TtsPlayerState.error;
      _errorMessage = 'Ingen text att läsa upp.';
      notifyListeners();
      return;
    }

    _currentIndex = 0;
    _state = TtsPlayerState.playing;
    notifyListeners();
    _userInitiatedStop = true;
    await _tts.stop();
    await _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= _sentences.length) return;
    final sentence = _sentences[_currentIndex];
    _nextSentenceTimer?.cancel();
    debugPrint(
      '[Tts] speak idx=$_currentIndex rate=${_mappedRate(_speechRate)} chars=${sentence.length}',
    );
    final result = await _tts.speak(sentence);
    debugPrint('[Tts] speak returned: $result');
    // Efter att speak() returnerat har vi definitivt initierat ett
    // nytt utterance - eventuell tidigare userInitiatedStop är passé.
    _userInitiatedStop = false;
    if (_state == TtsPlayerState.playing) {
      _tickOpenPlayingWall();
    }
    if (_state == TtsPlayerState.playing) {
      final dur = _estimateDuration(sentence, _speechRate);
      debugPrint('[Tts] scheduled next sentence in ${dur.inMilliseconds}ms');
      _nextSentenceTimer = Timer(dur, () {
        if (_state == TtsPlayerState.playing) {
          _tickClosePlayingWall();
          _playNextSentence();
        }
      });
    }
  }

  Future<void> _stopAndWait() async {
    _tickClosePlayingWall();
    _nextSentenceTimer?.cancel();
    _userInitiatedStop = true;
    await _tts.stop();
    // Browser Speech API behöver tid att städa innan nästa speak() accepteras.
    // Olika browsers behöver olika mycket - 150ms är säkrare än 50ms.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  Future<void> _playNextSentence() async {
    // _userInitiatedStop är ENBART för att skydda mot att speak() själv
    // triggar completion-handler omedelbart efter en cancel() — den
    // ska bara konsumeras EN gång och bara av completion-handler-vägen.
    // Om vi är "playing" och completion firar, är det legitim övergång.
    if (_state != TtsPlayerState.playing) {
      debugPrint('[Tts] _playNextSentence skipped, state=$_state');
      return;
    }
    if (_userInitiatedStop) {
      debugPrint('[Tts] _playNextSentence consumed userInitiatedStop flag');
      _userInitiatedStop = false;
      // Vi är mitt i en cancel/restart-sekvens; _speakCurrent anropas
      // av den som triggade stop:en.
      return;
    }
    if (_currentIndex < _sentences.length - 1) {
      _currentIndex++;
      debugPrint('[Tts] advancing to idx=$_currentIndex');
      notifyListeners();
      await _speakCurrent();
    } else {
      debugPrint('[Tts] reached end at idx=$_currentIndex');
      _tickClosePlayingWall();
      _flushListeningReport();
      _state = TtsPlayerState.idle;
      _currentIndex = -1;
      _nextSentenceTimer?.cancel();
      notifyListeners();
      onFinished?.call();
    }
  }

  Future<void> pause() async {
    if (_state != TtsPlayerState.playing) return;
    _nextSentenceTimer?.cancel();
    await _stopAndWait();
    _state = TtsPlayerState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    if (_state != TtsPlayerState.paused) return;
    _state = TtsPlayerState.playing;
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> stop() async {
    await _stopAndWait();
    _tickClosePlayingWall();
    _flushListeningReport();
    _state = TtsPlayerState.idle;
    _currentIndex = -1;
    notifyListeners();
  }

  Future<void> skipForward() async {
    if (_sentences.isEmpty) return;
    final wasPlayingOrPaused =
        _state == TtsPlayerState.playing || _state == TtsPlayerState.paused;

    await _stopAndWait();

    _currentIndex = (_currentIndex + 1).clamp(0, _sentences.length - 1);

    if (wasPlayingOrPaused) {
      _state = TtsPlayerState.playing;
      notifyListeners();
      await _speakCurrent();
    } else {
      notifyListeners();
    }
  }

  Future<void> skipBackward() async {
    if (_sentences.isEmpty) return;
    final wasPlayingOrPaused =
        _state == TtsPlayerState.playing || _state == TtsPlayerState.paused;

    await _stopAndWait();

    _currentIndex = (_currentIndex - 1).clamp(0, _sentences.length - 1);

    if (wasPlayingOrPaused) {
      _state = TtsPlayerState.playing;
      notifyListeners();
      await _speakCurrent();
    } else {
      notifyListeners();
    }
  }

  /// VO-08: hoppar till och spelar upp en given mening (tap i originaltexten).
  Future<void> playFrom(int sentenceIndex) async {
    if (_sentences.isEmpty) return;
    final target = sentenceIndex.clamp(0, _sentences.length - 1);
    await _stopAndWait();
    _currentIndex = target;
    _state = TtsPlayerState.playing;
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.75, 2.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kTtsSpeechRatePref, _speechRate);
    } catch (_) {
      // Uppläsning ska inte stoppas om disk/plattform nekade skrivning.
    }
    final mapped = _mappedRate(_speechRate);
    debugPrint(
      '[Tts] setSpeechRate appRate=$_speechRate mappedRate=$mapped kIsWeb=$kIsWeb',
    );
    await _tts.setSpeechRate(mapped);
    notifyListeners();
    if (_state == TtsPlayerState.playing && _currentIndex >= 0) {
      await _stopAndWait();
      await _speakCurrent();
    }
  }

  @override
  void dispose() {
    _nextSentenceTimer?.cancel();
    _tickClosePlayingWall();
    _flushListeningReport();
    _tts.stop();
    super.dispose();
  }
}
