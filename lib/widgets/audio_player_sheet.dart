import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai_service.dart';
import '../theme/mirai_tokens.dart';

const _kAudioRatePref = 'audio_rate';
const _kAudioRates = [0.75, 1.0, 1.25, 1.5, 2.0];

/// Visar servns/klientens faktiska felmeddelande när det är känt (t.ex.
/// "Dokumentet saknar text att läsa upp."), annars en generisk text.
String _friendlyAudioErrorMessage(Object? error) {
  final msg = switch (error) {
    AiAuthException(:final message) => message,
    AiInvalidInputException(:final message) => message,
    AiUnavailableException(:final message) => message,
    _ => null,
  };
  if (msg == null || msg.trim().isEmpty) {
    return 'Kunde inte spela upp dokumentet just nu. Testa igen om en stund.';
  }
  return msg;
}

/// Molnläge-spelare (VO-01): bakgrundsuppspelning med låsskärmskontroller.
///
/// [initialProgress]/[onPositionChanged] stöder VO-02:s fortsätt-lyssna.
/// [queueLabel]/[onNext]/[nextLoad] stöder VO-09:s kö-läge (förgenererar
/// nästa dokuments ljud medan nuvarande spelar).
Future<void> showAudioPlayerSheet(
  BuildContext context, {
  required String title,
  required String docId,
  required Future<DocumentAudioResult> Function() load,
  double? initialProgress,
  void Function(Duration position, Duration duration, bool completed)? onPositionChanged,
  String? queueLabel,
  VoidCallback? onNext,
  Future<DocumentAudioResult> Function()? nextLoad,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _AudioPlayerSheetBody(
      key: ValueKey('audio_player_$docId'),
      title: title,
      docId: docId,
      load: load,
      initialProgress: initialProgress,
      onPositionChanged: onPositionChanged,
      queueLabel: queueLabel,
      onNext: onNext,
      nextLoad: nextLoad,
    ),
  );
}

class _AudioPlayerSheetBody extends StatefulWidget {
  const _AudioPlayerSheetBody({
    super.key,
    required this.title,
    required this.docId,
    required this.load,
    this.initialProgress,
    this.onPositionChanged,
    this.queueLabel,
    this.onNext,
    this.nextLoad,
  });

  final String title;
  final String docId;
  final Future<DocumentAudioResult> Function() load;
  final double? initialProgress;
  final void Function(Duration position, Duration duration, bool completed)? onPositionChanged;

  /// t.ex. "2 av 5".
  final String? queueLabel;
  final VoidCallback? onNext;
  final Future<DocumentAudioResult> Function()? nextLoad;

  @override
  State<_AudioPlayerSheetBody> createState() => _AudioPlayerSheetBodyState();
}

class _AudioPlayerSheetBodyState extends State<_AudioPlayerSheetBody> {
  final AudioPlayer _player = AudioPlayer();
  DocumentAudioResult? _data;
  Object? _error;
  bool _loading = true;
  double _rate = 1.0;
  bool _seekedToInitial = false;
  DateTime? _lastPositionReport;
  bool _reportedCompleted = false;
  Future<DocumentAudioResult>? _nextPreload;

  @override
  void initState() {
    super.initState();
    if (widget.nextLoad != null) {
      // Förgenererar nästa dokuments ljud medan detta spelar (VO-09).
      _nextPreload = widget.nextLoad!();
      _nextPreload!.catchError((_) => const DocumentAudioResult(audioUrl: '', truncated: false));
    }
    _player.positionStream.listen((pos) {
      if (mounted) setState(() {});
      final dur = _player.duration;
      if (dur == null || dur <= Duration.zero) return;
      final now = DateTime.now();
      if (_lastPositionReport != null &&
          now.difference(_lastPositionReport!) < const Duration(seconds: 30)) {
        return;
      }
      _lastPositionReport = now;
      widget.onPositionChanged?.call(pos, dur, false);
    });
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() {});
      if (state.processingState == ProcessingState.completed && !_reportedCompleted) {
        _reportedCompleted = true;
        final dur = _player.duration ?? Duration.zero;
        widget.onPositionChanged?.call(dur, dur, true);
        if (widget.onNext != null) widget.onNext!();
      }
    });
    _kick();
  }

  void _reportPositionNow() {
    final dur = _player.duration;
    if (dur == null || dur <= Duration.zero) return;
    _lastPositionReport = DateTime.now();
    widget.onPositionChanged?.call(_player.position, dur, false);
  }

  Future<void> _loadSavedRate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_kAudioRatePref);
      if (saved != null && _kAudioRates.contains(saved)) {
        _rate = saved;
      }
    } catch (_) {
      // Standardhastighet räcker om prefs inte går att läsa.
    }
  }

  Future<void> _kick() async {
    await _loadSavedRate();
    try {
      await AudioSession.instance.then((s) => s.configure(const AudioSessionConfiguration.speech()));
      final data = await widget.load();
      if (!mounted) return;
      _data = data;
      _loading = false;
      setState(() {});
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(data.audioUrl),
          tag: MediaItem(
            id: widget.docId,
            title: widget.title,
            album: 'My Mirai',
          ),
        ),
      );
      await _player.setSpeed(_rate);
      final progress = widget.initialProgress;
      final dur = _player.duration;
      if (progress != null && progress > 0.02 && progress < 0.97 && dur != null) {
        final target = dur * progress;
        await _player.seek(target);
        _seekedToInitial = true;
      }
      await _player.play();
    } catch (e) {
      debugPrint('[FriendlyError] $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _togglePlay() async {
    if (_player.playerState.playing) {
      await _player.pause();
      _reportPositionNow();
    } else {
      await _player.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _skip(Duration delta) async {
    final dur = _player.duration ?? Duration.zero;
    var next = _player.position + delta;
    if (next < Duration.zero) next = Duration.zero;
    if (next > dur) next = dur;
    await _player.seek(next);
  }

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    await _player.setSpeed(rate);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kAudioRatePref, rate);
    } catch (_) {
      // Ignorera — hastigheten gäller ändå denna session.
    }
  }

  @override
  void dispose() {
    if (!_reportedCompleted) _reportPositionNow();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: MiraiTokens.bgRaised,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MiraiTokens.radiusLg),
            ),
            border: Border.all(color: MiraiTokens.borderSubtle),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              MiraiTokens.spaceLg,
              MiraiTokens.spaceMd,
              MiraiTokens.spaceLg,
              MiraiTokens.spaceLg + bottom,
            ),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MiraiTokens.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: MiraiTokens.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.queueLabel != null)
                          Text(
                            widget.queueLabel!,
                            style: tt.labelSmall?.copyWith(color: MiraiTokens.textTertiary),
                          ),
                        Text(
                          widget.title,
                          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Stäng',
                  ),
                ],
              ),
              const SizedBox(height: MiraiTokens.spaceSm),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(MiraiTokens.spaceXl),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: MiraiTokens.spaceMd),
                        Text('Förbereder uppläsning …'),
                      ],
                    ),
                  ),
                )
              else if (_error != null)
                Text(
                  _friendlyAudioErrorMessage(_error),
                  style: tt.bodyMedium?.copyWith(color: MiraiTokens.danger),
                )
              else if (_data != null) ...[
                if (_seekedToInitial)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MiraiTokens.spaceXs),
                    child: Text(
                      'Fortsätter där du var.',
                      style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                    ),
                  ),
                Builder(
                  builder: (_) {
                    final pos = _player.position;
                    final total = _player.duration ?? Duration.zero;
                    final maxMs = total.inMilliseconds;
                    if (maxMs <= 0) {
                      return const LinearProgressIndicator();
                    }
                    final v = pos.inMilliseconds / maxMs.toDouble();
                    return Slider(
                      value: v.clamp(0.0, 1.0),
                      onChanged: (x) async {
                        final ms = (x * maxMs).round();
                        await _player.seek(Duration(milliseconds: ms));
                      },
                    );
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _skip(const Duration(seconds: -15)),
                      icon: const Icon(Icons.replay_10_rounded),
                      tooltip: '15 sekunder bakåt',
                    ),
                    const SizedBox(width: MiraiTokens.spaceSm),
                    FilledButton.tonalIcon(
                      onPressed: _togglePlay,
                      icon: Icon(
                        _player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      ),
                      label: Text(_player.playing ? 'Pausa' : 'Spela'),
                    ),
                    const SizedBox(width: MiraiTokens.spaceSm),
                    IconButton(
                      onPressed: () => _skip(const Duration(seconds: 15)),
                      icon: const Icon(Icons.forward_10_rounded),
                      tooltip: '15 sekunder framåt',
                    ),
                    if (widget.onNext != null) ...[
                      const SizedBox(width: MiraiTokens.spaceSm),
                      IconButton(
                        onPressed: widget.onNext,
                        icon: const Icon(Icons.skip_next_rounded),
                        tooltip: 'Nästa',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: MiraiTokens.spaceSm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: MiraiTokens.spaceXs,
                  children: [
                    for (final r in _kAudioRates)
                      ChoiceChip(
                        label: Text('${r}x'),
                        selected: _rate == r,
                        onSelected: (_) => _setRate(r),
                      ),
                  ],
                ),
                if (_data!.truncated) ...[
                  const SizedBox(height: MiraiTokens.spaceSm),
                  Text(
                    'Texten var lång — uppläsningen täcker början.',
                    style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
