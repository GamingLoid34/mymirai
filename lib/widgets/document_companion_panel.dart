import 'dart:async';
import 'dart:io' show File;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config.dart';
import '../data/document_repository.dart';
import '../models/document.dart';
import '../models/document_chat_turn.dart';
import '../services/ai_service.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';

/// Anteckningar (synka till Firestore) + dokumentchatt / diktering (molnläge).
class DocumentCompanionPanel extends StatelessWidget {
  const DocumentCompanionPanel({
    super.key,
    required this.doc,
    required this.repository,
  });

  final UserDocument doc;
  final DocumentRepository repository;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ANTECKNINGAR',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: MiraiTokens.textTertiary,
              ),
        ),
        const SizedBox(height: MiraiTokens.spaceXs),
        DocumentUserNotesField(doc: doc, repository: repository),
        const SizedBox(height: MiraiTokens.spaceLg),
        Text(
          'CHATT OM DOKUMENTET',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: MiraiTokens.textTertiary,
              ),
        ),
        const SizedBox(height: MiraiTokens.spaceSm),
        if (kUseFirestoreHomework)
          DocumentChatSection(doc: doc, repository: repository)
        else
          Text(
            'Chatt och röst kräver molnläge (Firestore).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: MiraiTokens.textTertiary,
                ),
          ),
      ],
    );
  }
}

class DocumentUserNotesField extends StatefulWidget {
  const DocumentUserNotesField({
    super.key,
    required this.doc,
    required this.repository,
  });

  final UserDocument doc;
  final DocumentRepository repository;

  @override
  State<DocumentUserNotesField> createState() => _DocumentUserNotesFieldState();
}

class _DocumentUserNotesFieldState extends State<DocumentUserNotesField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.doc.userNotes ?? '',
  );
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  @override
  void didUpdateWidget(covariant DocumentUserNotesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.doc.userNotes ?? '';
    final old = oldWidget.doc.userNotes ?? '';
    if (next != old && !_focus.hasFocus) {
      _ctrl.text = next;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), () async {
      final t = _ctrl.text.trim();
      final next = t.isEmpty ? null : t;
      if (next == widget.doc.userNotes) return;
      try {
        await widget.repository.update(
          widget.doc.copyWith(userNotes: next),
        );
      } catch (_) {
        /* tyst; användaren ser ev. om de lämnar skärmen */
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      minLines: 3,
      maxLines: 8,
      decoration: const InputDecoration(
        hintText: 'Dina egna anteckningar (synkas)',
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => _scheduleSave(),
    );
  }
}

class DocumentChatSection extends StatefulWidget {
  const DocumentChatSection({
    super.key,
    required this.doc,
    required this.repository,
  });

  final UserDocument doc;
  final DocumentRepository repository;

  @override
  State<DocumentChatSection> createState() => _DocumentChatSectionState();
}

class _DocumentChatSectionState extends State<DocumentChatSection> {
  final _ctrl = TextEditingController();
  final _ai = AiService();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _recording = false;
  final _recorder = AudioRecorder();
  static const _suggestions = [
    'Sammanfatta dokumentet kort',
    'Vilka är viktigaste punkterna?',
    'Vad bör jag agera på först?',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  List<Map<String, String>> _historyFrom(List<DocumentChatTurn> turns) {
    final hist = <Map<String, String>>[];
    for (final t in turns) {
      final c = t.content.trim();
      if (c.isEmpty) continue;
      hist.add({
        'role':
            t.role == DocumentChatRole.user ? 'user' : 'assistant',
        'content': c,
      });
    }
    return hist;
  }

  Future<void> _send(List<DocumentChatTurn> currentTurns) async {
    final msg = _ctrl.text.trim();
    if (msg.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _ai.chatWithDocument(
        documentId: widget.doc.id,
        userMessage: msg,
        history: _historyFrom(currentTurns),
      );
      if (mounted) _ctrl.clear();
    } catch (e) {
      if (mounted) {
        showFriendlySnack(
          context,
          'Hoppsan – det gick inte att skicka meddelandet. Testa igen om en stund.',
          error: e,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (kIsWeb) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != widget.doc.ownerUid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Du måste vara inloggad som dokumentägare.')),
        );
      }
      return;
    }
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path == null || path.isEmpty) return;
      try {
        final file = File(path);
        final name =
            'doc_${widget.doc.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final ref = FirebaseStorage.instance.ref('users/$uid/voice/$name');
        await ref.putFile(
          file,
          SettableMetadata(contentType: 'audio/mp4'),
        );
        final text = await _ai.transcribeUserAudio(
          storagePath: ref.fullPath,
          mimeType: 'audio/mp4',
        );
        if (!mounted) return;
        _ctrl.text = _ctrl.text.trim().isEmpty
            ? text
            : '${_ctrl.text.trim()} $text';
      } catch (e) {
        if (mounted) {
          showFriendlySnack(
            context,
            'Hoppsan – det gick inte att tolka rösten. Testa igen om en stund.',
            error: e,
          );
        }
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon saknas eller nekades.')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/dict_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    setState(() => _recording = true);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return StreamBuilder<List<DocumentChatTurn>>(
      stream: widget.repository.watchDocumentChatTurns(widget.doc.id),
      builder: (context, snap) {
        final turns = snap.data ?? const <DocumentChatTurn>[];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: MiraiTokens.bgRaised,
                borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                border: Border.all(color: MiraiTokens.borderSubtle),
              ),
              child: turns.isEmpty
                  ? Center(
                      // Scrollbar tom-state: med tangentbordet uppe kan ytan bli
                      // lägre än innehållet (RenderFlex-overflow annars).
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(MiraiTokens.spaceMd),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Ställ en fråga om texten. AI svarar utifrån dokumentet.',
                              style: tt.bodySmall?.copyWith(
                                color: MiraiTokens.textTertiary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: MiraiTokens.spaceSm),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: MiraiTokens.spaceXs,
                              runSpacing: MiraiTokens.spaceXs,
                              children: [
                                for (final s in _suggestions)
                                  ActionChip(
                                    label: Text(s),
                                    onPressed: () {
                                      _ctrl.text = s;
                                      _send(turns);
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(MiraiTokens.spaceSm),
                      itemCount: turns.length,
                      itemBuilder: (ctx, i) {
                        final t = turns[i];
                        final mine = t.role == DocumentChatRole.user;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            constraints: const BoxConstraints(maxWidth: 300),
                            decoration: BoxDecoration(
                              color: mine
                                  ? MiraiTokens.accent.withValues(alpha: 0.2)
                                  : MiraiTokens.bgInteractive,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              t.content,
                              style: tt.bodySmall?.copyWith(height: 1.35),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: MiraiTokens.spaceSm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!kIsWeb)
                  IconButton.filledTonal(
                    tooltip: _recording ? 'Stoppa och skicka till text' : 'Röst',
                    onPressed: _sending ? null : _toggleVoice,
                    icon: Icon(
                      _recording ? Icons.stop_rounded : Icons.mic_none_rounded,
                      color: _recording ? MiraiTokens.danger : null,
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Fråga…',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(turns),
                  ),
                ),
                const SizedBox(width: MiraiTokens.spaceXs),
                IconButton.filled(
                  onPressed: _sending ? null : () => _send(turns),
                  icon: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
