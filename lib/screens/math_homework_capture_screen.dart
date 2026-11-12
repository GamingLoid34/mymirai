import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../data/deck_repository.dart';
import '../data/homework_repository.dart';
import '../data/homework_storage_upload.dart';
import '../models/homework_attachment.dart';
import '../models/homework_item.dart';
import '../models/math_problem_entry.dart';
import '../services/ai_service.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../util/merge_extracted_texts.dart';
import '../util/subject_suggestions.dart';
import '../widgets/subject_field.dart';
import 'homework_detail_screen.dart';

/// Matteläxa: foto → extraherad text → `parseMathProblems`.
class MathHomeworkCaptureScreen extends StatefulWidget {
  const MathHomeworkCaptureScreen({
    super.key,
    required this.repository,
    required this.familyId,
    required this.assignedToUserId,
    this.deckRepository,
  });

  final HomeworkRepository repository;
  final String familyId;
  final String assignedToUserId;
  final DeckRepository? deckRepository;

  @override
  State<MathHomeworkCaptureScreen> createState() => _MathHomeworkCaptureScreenState();
}

class _MathHomeworkCaptureScreenState extends State<MathHomeworkCaptureScreen> {
  final _titleCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController();
  final _picker = ImagePicker();
  final _ai = AiService();

  Uint8List? _bytes;
  String? _imageName;
  DateTime? _dueAt;
  bool _busy = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subjectCtrl.dispose();
    _gradeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final image = await _picker.pickImage(source: src, imageQuality: 92);
    if (image == null) return;
    final b = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _imageName = image.name.isNotEmpty ? image.name : 'foto.jpg';
    });
  }

  Future<void> _chooseSource() async {
    final c = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(ctx, 'cam'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Bilder'),
              onTap: () => Navigator.pop(ctx, 'gal'),
            ),
          ],
        ),
      ),
    );
    if (c == 'cam') await _pick(ImageSource.camera);
    if (c == 'gal') await _pick(ImageSource.gallery);
  }

  Future<void> _save() async {
    if (_bytes == null ||
        (_imageName ?? '').isEmpty ||
        _titleCtrl.text.trim().isEmpty ||
        _busy) {
      if (_bytes == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Välj eller ta en bild först')),
        );
      }
      return;
    }

    setState(() => _busy = true);

    try {
      final now = DateTime.now();
      final ghText = _gradeCtrl.text.trim();
      int? gradeHint;
      if (ghText.isNotEmpty) {
        gradeHint = int.tryParse(ghText);
      }

      var draft = HomeworkItem(
        id: '',
        familyId: widget.familyId,
        assignedToUserId: widget.assignedToUserId,
        subject:
            _subjectCtrl.text.trim().isEmpty ? 'Matematik' : _subjectCtrl.text.trim(),
        title: _titleCtrl.text.trim(),
        dueAt: _dueAt,
        status: HomeworkStatus.todo,
        homeworkType: 'math',
        vocabulary: const [],
        mathProblems: const [],
        gradeHint: gradeHint,
        attachmentFileName: _imageName,
        attachmentMimeType: 'image/jpeg',
        createdAt: now,
        updatedAt: now,
      );

      final id = await widget.repository.create(draft);
      draft = draft.copyWith(id: id);

      final localDemo = kUseFirestoreHomework && id.startsWith('dev-');
      if (_bytes != null && !localDemo) {
        final url = await uploadHomeworkAttachmentBytes(
          familyId: widget.familyId,
          homeworkId: id,
          fileName: _imageName!,
          bytes: _bytes!,
          contentType: 'image/jpeg',
        );
        draft = draft.copyWith(
          attachmentStorageUrl: url,
          attachments: [
            HomeworkAttachment(
              fileName: _imageName!,
              mimeType: 'image/jpeg',
              storageUrl: url,
              extractedText: null,
              addedAt: now,
            ),
          ],
        );
        await widget.repository.update(draft);

        final extracted = await _ai.extractFromAttachment(id, attachmentIndex: 0);
        draft = withAttachmentExtractApplied(draft, 0, extracted.text);
        await widget.repository.update(draft);

        if ((extracted.text).trim().length >= 10) {
          try {
            final probs = await _ai.parseMathProblems(extracted.text);
            draft = draft.copyWith(
              mathProblems:
                  probs.map((p) => MathProblemEntry(originalText: p.originalText)).toList(),
            );
            await widget.repository.update(draft);
          } catch (e) {
            if (mounted) {
              showFriendlySnack(
                context,
                'Hoppsan – texten hittades men inga uppgifter kunde tolkas.',
                error: e,
              );
            }
          }
        }
      }

      if (!mounted) return;
      if (localDemo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demo-läge: matte med foto kräver molnläxa.'),
          ),
        );
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeworkDetailScreen(
            repository: widget.repository,
            deckRepository: widget.deckRepository,
            familyId: widget.familyId,
            assignedToUserId: widget.assignedToUserId,
            homeworkId: id,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara läxan. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _due() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Matteläxa (foto)')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(MiraiTokens.spaceLg),
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titel',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: MiraiTokens.spaceMd),
            StreamBuilder<List<HomeworkItem>>(
              stream: widget.repository.watchForFamily(
                familyId: widget.familyId,
                assignedToUserId: widget.assignedToUserId,
              ),
              builder: (context, snap) {
                final raw = snap.data ?? const <HomeworkItem>[];
                final list = kUseFirestoreHomework
                    ? raw.where((h) => !h.id.startsWith('dev-')).toList()
                    : raw;
                return SubjectField(
                  controller: _subjectCtrl,
                  options: mergedSubjectOptions(list),
                  label: 'Ämne',
                );
              },
            ),
            const SizedBox(height: MiraiTokens.spaceMd),
            TextField(
              controller: _gradeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Årskurs (valfritt, 1–9)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: MiraiTokens.spaceSm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _due,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _dueAt == null
                      ? 'Deadline (valfritt)'
                      : 'Deadline: ${_dueAt!.day}/${_dueAt!.month}',
                ),
              ),
            ),
            const SizedBox(height: MiraiTokens.spaceMd),
            OutlinedButton.icon(
              onPressed: _busy ? null : _chooseSource,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_bytes == null ? 'Lägg till foto' : 'Byt foto'),
            ),
            if (_bytes != null) ...[
              const SizedBox(height: MiraiTokens.spaceMd),
              ClipRRect(
                borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                child: Image.memory(_bytes!, height: 180, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: MiraiTokens.spaceXl),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Bearbetar…' : 'Spara och läs av'),
            ),
            const SizedBox(height: MiraiTokens.spaceSm),
            Text(
              'Bilden skickas till molnet för OCR. Efter sparning kan du öppna läxan och '
              'få steg-för-steg-hjälp.',
              style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
