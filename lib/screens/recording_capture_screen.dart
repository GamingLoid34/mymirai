import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../data/document_repository.dart';
import '../data/document_storage_upload.dart';
import '../models/document.dart';
import '../services/ai_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../util/recording_settings.dart';
import 'document_detail_screen.dart';

enum _CaptureState { recording, paused, processing }

class RecordingCaptureScreen extends StatefulWidget {
  const RecordingCaptureScreen({
    super.key,
    required this.repository,
    required this.ownerUid,
  });

  final DocumentRepository repository;
  final String ownerUid;

  @override
  State<RecordingCaptureScreen> createState() => _RecordingCaptureScreenState();
}

class _RecordingCaptureScreenState extends State<RecordingCaptureScreen> {
  final _recorder = AudioRecorder();
  final _ai = AiService();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  _CaptureState _state = _CaptureState.recording;
  String _languageCode = 'sv-SE';
  String? _recordedPath;
  String _pipelineLabel = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _languageCode = await getRecordingLanguageCode();
    if (!mounted) return;
    setState(() {});
    await _startRecording();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      showFriendlySnack(context, 'Mikrofon saknas eller nekades.');
      Navigator.of(context).pop();
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _recordedPath = path;
    _elapsed = Duration.zero;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
    if (mounted) setState(() => _state = _CaptureState.recording);
  }

  Future<void> _togglePause() async {
    if (_state == _CaptureState.recording) {
      await _recorder.pause();
      _ticker?.cancel();
      if (mounted) setState(() => _state = _CaptureState.paused);
    } else if (_state == _CaptureState.paused) {
      await _recorder.resume();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
      });
      if (mounted) setState(() => _state = _CaptureState.recording);
    }
  }

  Future<void> _setLanguage(String code) async {
    setState(() => _languageCode = code);
    await setRecordingLanguageCode(code);
  }

  Future<void> _stopAndSave() async {
    _ticker?.cancel();
    setState(() => _state = _CaptureState.processing);
    final path = await _recorder.stop();
    if (path == null || _recordedPath == null) {
      if (!mounted) return;
      showFriendlySnack(context, 'Hoppsan – inspelningen gick förlorad. Testa igen.');
      Navigator.of(context).pop();
      return;
    }

    String? documentId;
    try {
      setState(() => _pipelineLabel = 'Laddar upp …');
      final file = File(path);
      final bytes = Uint8List.fromList(await file.readAsBytes());
      final title = 'Inspelning ${DateFormat('d MMM HH:mm', 'sv').format(DateTime.now())}';
      final now = DateTime.now();
      documentId = await widget.repository.create(
        UserDocument(
          id: '',
          ownerUid: widget.ownerUid,
          title: title,
          sourceType: 'recording',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final fileName = 'original.m4a';
      final uploaded = await uploadDocumentAttachmentBytes(
        ownerUid: widget.ownerUid,
        documentId: documentId,
        fileName: fileName,
        bytes: bytes,
        contentTypeHint: 'audio/mp4',
      );
      final attachment = DocumentAttachment(
        storagePath: uploaded.storagePath,
        fileName: fileName,
        sizeBytes: uploaded.sizeBytes,
        mimeType: uploaded.effectiveMimeType,
      );
      await widget.repository.update(
        UserDocument(
          id: documentId,
          ownerUid: widget.ownerUid,
          title: title,
          sourceType: 'recording',
          attachment: attachment,
          attachmentStorageUrl: uploaded.downloadUrl,
          createdAt: now,
          updatedAt: now,
        ),
      );

      if (!mounted) return;
      setState(() => _pipelineLabel = 'Transkriberar …');
      await _ai.transcribeRecording(documentId: documentId, languageCode: _languageCode);

      if (!mounted) return;
      setState(() => _pipelineLabel = 'Sammanfattar …');
      await _ai.summarizeRecording(documentId: documentId);

      await _maybeAutoDeleteAudio(documentId, attachment.storagePath);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DocumentDetailScreen(
            repository: widget.repository,
            ownerUid: widget.ownerUid,
            documentId: documentId!,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (documentId != null) {
        // Dokumentet finns kvar med det som hann bli klart; öppna det så
        // användaren kan försöka igen per steg i detaljvyn.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => DocumentDetailScreen(
              repository: widget.repository,
              ownerUid: widget.ownerUid,
              documentId: documentId!,
            ),
          ),
        );
        showFriendlySnack(
          context,
          'Ett steg misslyckades. Läxan/anteckningen finns kvar — försök igen i vyn.',
          error: e,
        );
      } else {
        showFriendlySnack(
          context,
          'Hoppsan – det gick inte att spara inspelningen. Testa igen.',
          error: e,
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _maybeAutoDeleteAudio(String documentId, String storagePath) async {
    if (!await hasAskedAutoDeleteRecording()) {
      await markAskedAutoDeleteRecording();
      if (!mounted) return;
      final enable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Radera ljudfilen efter transkription?'),
          content: const Text(
            'Sparar bara transkript och sammanfattning, inte själva ljudinspelningen. '
            'Du kan ändra detta senare under Verktyg.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Nej, behåll ljudet'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ja, radera'),
            ),
          ],
        ),
      );
      if (enable == true) {
        await setAutoDeleteRecordingAudio(true);
      }
    }

    if (await getAutoDeleteRecordingAudio()) {
      try {
        await FirebaseStorage.instance.ref(storagePath).delete();
        await widget.repository.update(
          (await widget.repository.getById(documentId))?.copyWith(clearAttachment: true) ??
              UserDocument(
                id: documentId,
                ownerUid: widget.ownerUid,
                title: '',
                sourceType: 'recording',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
        );
      } catch (_) {
        // Rensning är bäst-effort; transkript/sammanfattning är redan sparat.
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return PopScope(
      canPop: _state != _CaptureState.processing,
      child: Scaffold(
        appBar: AppBar(
          leading: _state == _CaptureState.processing
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          title: const Text('Spela in'),
        ),
        body: SafeArea(
          child: Center(
            child: MiraiAdaptiveBox(
              child: Padding(
                padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_state == _CaptureState.processing) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: MiraiTokens.spaceMd),
                      Text(_pipelineLabel, style: tt.bodyLarge),
                    ] else ...[
                      _PulsingDot(paused: _state == _CaptureState.paused),
                      const SizedBox(height: MiraiTokens.spaceLg),
                      Text(
                        _formatElapsed(_elapsed),
                        style: tt.headlineLarge?.copyWith(
                          fontSize: 48,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: MiraiTokens.spaceLg),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: MiraiTokens.spaceXs,
                        children: [
                          ChoiceChip(
                            label: const Text('Svenska'),
                            selected: _languageCode == 'sv-SE',
                            onSelected: (_) => _setLanguage('sv-SE'),
                          ),
                          ChoiceChip(
                            label: const Text('Engelska'),
                            selected: _languageCode == 'en-US',
                            onSelected: (_) => _setLanguage('en-US'),
                          ),
                        ],
                      ),
                      const SizedBox(height: MiraiTokens.spaceLg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _togglePause,
                            icon: Icon(
                              _state == _CaptureState.paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                            ),
                            label: Text(_state == _CaptureState.paused ? 'Fortsätt' : 'Pausa'),
                          ),
                          const SizedBox(width: MiraiTokens.spaceMd),
                          FilledButton.icon(
                            onPressed: _stopAndSave,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('Stoppa'),
                          ),
                        ],
                      ),
                      const SizedBox(height: MiraiTokens.spaceLg),
                      Text(
                        'Spela bara in samtal du deltar i och där inspelning är okej på din arbetsplats.',
                        style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.paused});
  final bool paused;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paused) {
      return const Icon(Icons.pause_circle_outline_rounded, size: 64, color: MiraiTokens.textTertiary);
    }
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl),
      child: const Icon(Icons.fiber_manual_record_rounded, size: 64, color: MiraiTokens.danger),
    );
  }
}
