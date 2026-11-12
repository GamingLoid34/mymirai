import 'dart:async';
import 'dart:io' show File;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../data/document_repository.dart';
import '../models/document.dart';
import '../services/ai_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import 'document_detail_screen.dart';

/// VO-07: minimal skärm för en snabb anteckning — skriven eller intalad.
class NoteCaptureScreen extends StatefulWidget {
  const NoteCaptureScreen({
    super.key,
    required this.repository,
    required this.ownerUid,
    this.initialText,
  });

  final DocumentRepository repository;
  final String ownerUid;

  /// VO-10: förifylld text från en delning (t.ex. delad text från en annan app).
  final String? initialText;

  @override
  State<NoteCaptureScreen> createState() => _NoteCaptureScreenState();
}

class _NoteCaptureScreenState extends State<NoteCaptureScreen> {
  final _textCtrl = TextEditingController();
  final _ai = AiService();
  final _recorder = AudioRecorder();
  bool _saving = false;
  bool _recording = false;
  bool _transcribing = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialText?.trim();
    if (initial != null && initial.isNotEmpty) {
      _textCtrl.text = initial;
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  String _suggestedTitle() {
    final firstLine = _textCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return 'Anteckning';
    return firstLine.length > 60 ? firstLine.substring(0, 60) : firstLine;
  }

  Future<void> _save() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final id = await widget.repository.create(
        UserDocument(
          id: '',
          ownerUid: widget.ownerUid,
          title: _suggestedTitle(),
          extractedText: text,
          sourceType: 'note',
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DocumentDetailScreen(
            repository: widget.repository,
            ownerUid: widget.ownerUid,
            documentId: id,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara anteckningen. Testa igen om en stund.',
        error: e,
      );
    }
  }

  Future<void> _toggleDictation() async {
    if (kIsWeb) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path == null || path.isEmpty) return;
      await _transcribeAndOfferChoice(path, uid);
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      showFriendlySnack(context, 'Mikrofon saknas eller nekades.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/note_dictation_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() => _recording = true);
  }

  Future<void> _transcribeAndOfferChoice(String localPath, String uid) async {
    setState(() => _transcribing = true);
    try {
      final file = File(localPath);
      final name = 'note_dictation_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final ref = FirebaseStorage.instance.ref('users/$uid/voice/$name');
      await ref.putFile(file, SettableMetadata(contentType: 'audio/mp4'));
      final raw = await _ai.transcribeUserAudio(storagePath: ref.fullPath, mimeType: 'audio/mp4');
      if (!mounted) return;

      String? polished;
      try {
        polished = await _ai.polishDictation(text: raw);
      } catch (_) {
        polished = null;
      }
      if (!mounted) return;

      if (polished == null || polished.trim().isEmpty) {
        _insertDictatedText(raw);
        return;
      }
      await _showPolishChoiceSheet(raw: raw, polished: polished);
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att tolka rösten. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  void _insertDictatedText(String text) {
    final current = _textCtrl.text;
    _textCtrl.text = current.trim().isEmpty ? text : '$current $text';
    _textCtrl.selection = TextSelection.collapsed(offset: _textCtrl.text.length);
  }

  Future<void> _showPolishChoiceSheet({required String raw, required String polished}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MiraiTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Använd städad eller rå text?', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: MiraiTokens.spaceMd),
              Text('Städad', style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: MiraiTokens.spaceXs),
              Container(
                padding: const EdgeInsets.all(MiraiTokens.spaceSm),
                decoration: BoxDecoration(
                  color: MiraiTokens.bgRaised,
                  borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                  border: Border.all(color: MiraiTokens.borderSubtle),
                ),
                child: Text(polished),
              ),
              const SizedBox(height: MiraiTokens.spaceMd),
              Text('Rå transkription', style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: MiraiTokens.spaceXs),
              Container(
                padding: const EdgeInsets.all(MiraiTokens.spaceSm),
                decoration: BoxDecoration(
                  color: MiraiTokens.bgRaised,
                  borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                  border: Border.all(color: MiraiTokens.borderSubtle),
                ),
                child: Text(raw),
              ),
              const SizedBox(height: MiraiTokens.spaceLg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop('raw'),
                      child: const Text('Använd rå'),
                    ),
                  ),
                  const SizedBox(width: MiraiTokens.spaceSm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop('polished'),
                      child: const Text('Använd städad'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    _insertDictatedText(choice == 'polished' ? polished : raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Snabb anteckning'),
        actions: [
          if (!kIsWeb)
            IconButton(
              tooltip: _recording ? 'Stoppa och skicka till text' : 'Prata in anteckning',
              onPressed: _transcribing ? null : _toggleDictation,
              icon: _transcribing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _recording ? Icons.stop_rounded : Icons.mic_none_rounded,
                      color: _recording ? MiraiTokens.danger : null,
                    ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: MiraiAdaptiveBox(
            child: Padding(
              padding: const EdgeInsets.all(MiraiTokens.spaceLg),
              child: TextField(
                controller: _textCtrl,
                autofocus: true,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Skriv en tanke …',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MiraiTokens.spaceLg),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Spara'),
          ),
        ),
      ),
    );
  }
}
