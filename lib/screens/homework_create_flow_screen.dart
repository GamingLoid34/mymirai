import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../data/local_homework_repository.dart';
import 'local_homework_form.dart';
import '../data/deck_repository.dart';
import '../data/homework_repository.dart';
import '../data/homework_storage_upload.dart';
import '../models/homework_attachment.dart';
import '../models/homework_item.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../util/merge_extracted_texts.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../util/subject_suggestions.dart';
import '../widgets/subject_field.dart';
import 'homework_detail_screen.dart';

/// Max bilagor vid skapa (Firestore-extraktion köas per fil).
const _kMaxCreateAttachments = 8;

class _CreateDraftFile {
  _CreateDraftFile({required this.bytes, required this.fileName})
      : role = HomeworkAttachmentRole.mixed;
  final Uint8List bytes;
  final String fileName;
  HomeworkAttachmentRole role;
  String get mime => _guessMimeType(fileName);
}

class HomeworkCreateFlowScreen extends StatefulWidget {
  const HomeworkCreateFlowScreen({
    super.key,
    required this.repository,
    this.deckRepository,
    required this.familyId,
    required this.assignedToUserId,
    this.authService,
  });

  final HomeworkRepository repository;
  final DeckRepository? deckRepository;
  final String familyId;
  final String assignedToUserId;
  final AuthService? authService;

  @override
  State<HomeworkCreateFlowScreen> createState() => _HomeworkCreateFlowScreenState();
}

class _HomeworkCreateFlowScreenState extends State<HomeworkCreateFlowScreen> {
  final _titleCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _pageCtrl = PageController();
  final _picker = ImagePicker();
  final _ai = AiService();
  int _currentStep = 0;
  DateTime? _dueAt;
  bool _saving = false;

  final List<_CreateDraftFile> _pickedAttachments = [];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subjectCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final r =
        await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    if (r == null || r.files.isEmpty) return;
    var hitLimit = false;
    setState(() {
      for (final f in r.files) {
        if (_pickedAttachments.length >= _kMaxCreateAttachments) {
          hitLimit = true;
          break;
        }
        if (f.bytes != null && f.name.trim().isNotEmpty) {
          _pickedAttachments.add(
            _CreateDraftFile(bytes: f.bytes!, fileName: f.name),
          );
        }
      }
    });
    if (hitLimit && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Max $_kMaxCreateAttachments bilagor — några hoppades över.'),
        ),
      );
    }
  }

  Future<void> _pickCamera() async {
    if (_pickedAttachments.length >= _kMaxCreateAttachments) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Max $_kMaxCreateAttachments bilagor.')),
        );
      }
      return;
    }
    final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 95);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(
      () => _pickedAttachments.add(_CreateDraftFile(bytes: bytes, fileName: image.name)),
    );
  }

  Future<void> _pickGallery() async {
    if (_pickedAttachments.length >= _kMaxCreateAttachments) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Max $_kMaxCreateAttachments bilagor.')),
        );
      }
      return;
    }
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(
      () => _pickedAttachments.add(_CreateDraftFile(bytes: bytes, fileName: image.name)),
    );
  }

  void _removePickedAt(int index) {
    if (index < 0 || index >= _pickedAttachments.length) return;
    setState(() => _pickedAttachments.removeAt(index));
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Ta foto'),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Välj bild'),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('Välj fil'),
              onTap: () => Navigator.of(ctx).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'camera') await _pickCamera();
    if (choice == 'gallery') await _pickGallery();
    if (choice == 'file') await _pickDocument();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      var draft = HomeworkItem(
        id: '',
        familyId: widget.familyId,
        assignedToUserId: widget.assignedToUserId,
        subject: _subjectCtrl.text.trim().isEmpty ? 'Ämne' : _subjectCtrl.text.trim(),
        title: _titleCtrl.text.trim(),
        dueAt: _dueAt,
        status: HomeworkStatus.todo,
        attachmentFileName:
            _pickedAttachments.isNotEmpty ? _pickedAttachments.first.fileName : null,
        attachmentMimeType:
            _pickedAttachments.isNotEmpty ? _pickedAttachments.first.mime : null,
        attachmentStorageUrl: null,
        createdAt: now,
        updatedAt: now,
      );
      final id = await widget.repository.create(draft);
      draft = draft.copyWith(id: id);
      final isLocalOnlyDemo = kUseFirestoreHomework && id.startsWith('dev-');

      if (_pickedAttachments.isNotEmpty) {
        final attachments = <HomeworkAttachment>[];
        final nowTs = DateTime.now();
        for (final p in _pickedAttachments) {
          final url = await uploadHomeworkAttachmentBytes(
            familyId: widget.familyId,
            homeworkId: id,
            fileName: p.fileName,
            bytes: p.bytes,
            contentType: p.mime,
          );
          final mt = p.mime.trim().isEmpty ? 'application/octet-stream' : p.mime.trim();
          attachments.add(
            HomeworkAttachment(
              fileName: p.fileName,
              mimeType: mt,
              storageUrl: url,
              extractedText: null,
              addedAt: nowTs,
            ),
          );
        }
        final primary = attachments.first;
        draft = draft.copyWith(
          attachmentStorageUrl: primary.storageUrl,
          attachmentFileName: primary.fileName,
          attachmentMimeType: primary.mimeType,
          attachments: attachments,
        );
        await widget.repository.update(draft);
        if (!isLocalOnlyDemo && attachments.isNotEmpty) {
          unawaited(_runSequentialExtractions(id, draft));
        }
      }
      if (isLocalOnlyDemo && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Den här läxan finns bara lokalt (gammal demo-data). Skapa en ny.'),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeworkDetailScreen(
            repository: widget.repository,
            deckRepository: widget.deckRepository,
            familyId: widget.familyId,
            assignedToUserId: widget.assignedToUserId,
            homeworkId: id,
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara läxan. Testa igen om en stund.',
        error: e,
      );
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDate: _dueAt ?? DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository is LocalHomeworkRepository) {
      final now = DateTime.now();
      return LocalHomeworkForm(heading: 'Ny läxa', initial: HomeworkItem(id: '',
        familyId: widget.familyId, assignedToUserId: widget.assignedToUserId, title: '', subject: '',
        status: HomeworkStatus.todo, createdAt: now, updatedAt: now),
        onSave: (draft) async { await widget.repository.create(draft); });
    }
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: MiraiAdaptiveBox(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MiraiTokens.spaceLg, vertical: 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (_currentStep == 0) {
                            Navigator.of(context).pop();
                          } else {
                            setState(() => _currentStep = 0);
                            _pageCtrl.previousPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        icon: Icon(_currentStep == 0 ? Icons.close_rounded : Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          _StepBar(active: _currentStep == 0),
                          const SizedBox(width: 4),
                          _StepBar(active: _currentStep == 1),
                        ],
                      ),
                      const Spacer(),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      ListView(
                        padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                        children: [
                          Text('Vad är läxan?', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: MiraiTokens.spaceXs),
                          Text(
                            'Ladda upp materialet eller skriv själv.',
                            style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                          ),
                          const SizedBox(height: MiraiTokens.spaceLg),
                          InkWell(
                            onTap: _pickAttachment,
                            borderRadius: BorderRadius.circular(MiraiTokens.radiusLg),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
                              decoration: BoxDecoration(
                                color: MiraiTokens.bgRaised,
                                borderRadius: BorderRadius.circular(MiraiTokens.radiusLg),
                                border: Border.all(
                                  color: MiraiTokens.accentMuted,
                                  width: MiraiTokens.borderThin,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: MiraiTokens.accentSoft,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Icon(
                                      _pickedAttachments.isEmpty ? Icons.add_rounded : Icons.library_add_check_rounded,
                                      color: MiraiTokens.accent,
                                    ),
                                  ),
                                  const SizedBox(height: MiraiTokens.spaceSm),
                                  Text(
                                    _pickedAttachments.isEmpty
                                        ? 'Foto eller fil(er)'
                                        : '${_pickedAttachments.length} källa${_pickedAttachments.length == 1 ? '' : 'or'}',
                                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _pickedAttachments.isEmpty
                                        ? 'Tap för att lägga till — flera filer möjligt'
                                        : 'Tap för att lägga till fler',
                                    style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_pickedAttachments.isNotEmpty) ...[
                            const SizedBox(height: MiraiTokens.spaceSm),
                            Text(
                              'Roll per fil (v6): Q&A → flashcards; sammanfattning → lyssna.',
                              style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                            ),
                            const SizedBox(height: MiraiTokens.spaceXs),
                            ...List.generate(_pickedAttachments.length, (i) {
                              final d = _pickedAttachments[i];
                              final name = d.fileName;
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.attach_file_rounded, size: 20, color: MiraiTokens.textSecondary),
                                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
                                subtitle: Text(
                                  d.role.labelSv,
                                  style: tt.bodySmall?.copyWith(color: MiraiTokens.accent),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    PopupMenuButton<HomeworkAttachmentRole>(
                                      tooltip: 'Roll',
                                      icon: Icon(Icons.tune_rounded, size: 20, color: MiraiTokens.textSecondary),
                                      onSelected: (r) =>
                                          setState(() => _pickedAttachments[i].role = r),
                                      itemBuilder: (ctx) => [
                                        for (final r in HomeworkAttachmentRole.values)
                                          PopupMenuItem(
                                            value: r,
                                            child: Text(r.labelSv),
                                          ),
                                      ],
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.close_rounded, size: 20, color: MiraiTokens.textSecondary),
                                      onPressed: _saving ? null : () => _removePickedAt(i),
                                      tooltip: 'Ta bort',
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          const SizedBox(height: MiraiTokens.spaceLg),
                          Row(
                            children: [
                              const Expanded(child: Divider(color: MiraiTokens.borderSubtle)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: MiraiTokens.spaceSm),
                                child: Text('eller', style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary)),
                              ),
                              const Expanded(child: Divider(color: MiraiTokens.borderSubtle)),
                            ],
                          ),
                          const SizedBox(height: MiraiTokens.spaceLg),
                          _FieldBox(
                            label: 'Titel',
                            hint: 'T.ex. Vikingatiden',
                            controller: _titleCtrl,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: MiraiTokens.spaceSm),
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
                                label: 'Ämne (valfritt)',
                                hint: 'T.ex. Historia',
                              );
                            },
                          ),
                          const SizedBox(height: MiraiTokens.spaceLg),
                          FilledButton(
                            onPressed: _titleCtrl.text.trim().isEmpty
                                ? null
                                : () {
                                    setState(() => _currentStep = 1);
                                    _pageCtrl.nextPage(
                                      duration: const Duration(milliseconds: 220),
                                      curve: Curves.easeOut,
                                    );
                                  },
                            child: const Text('Nästa'),
                          ),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                        children: [
                          Text('När ska den vara klar?', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: MiraiTokens.spaceXs),
                          Text(
                            'Hoppa om du inte vet - det går att ändra.',
                            style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                          ),
                          const SizedBox(height: MiraiTokens.spaceLg),
                          Row(
                            children: [
                              Expanded(child: _QuickDateCard(label: 'Imorgon', date: DateTime.now().add(const Duration(days: 1)), selected: _isSameDay(_dueAt, DateTime.now().add(const Duration(days: 1))), onTap: () => setState(() => _dueAt = DateTime.now().add(const Duration(days: 1))))),
                              const SizedBox(width: MiraiTokens.spaceXs),
                              Expanded(child: _QuickDateCard(label: 'Om 3 dagar', date: DateTime.now().add(const Duration(days: 3)), selected: _isSameDay(_dueAt, DateTime.now().add(const Duration(days: 3))), onTap: () => setState(() => _dueAt = DateTime.now().add(const Duration(days: 3))))),
                              const SizedBox(width: MiraiTokens.spaceXs),
                              Expanded(child: _QuickDateCard(label: 'Om 1 vecka', date: DateTime.now().add(const Duration(days: 7)), selected: _isSameDay(_dueAt, DateTime.now().add(const Duration(days: 7))), onTap: () => setState(() => _dueAt = DateTime.now().add(const Duration(days: 7))))),
                            ],
                          ),
                          const SizedBox(height: MiraiTokens.spaceMd),
                          ListTile(
                            tileColor: MiraiTokens.bgRaised,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                              side: const BorderSide(color: MiraiTokens.borderSubtle),
                            ),
                            leading: const Icon(Icons.calendar_today_outlined),
                            title: Text(_dueAt == null ? 'Välj annat datum' : 'Valt datum: ${_dueAt!.day}/${_dueAt!.month}/${_dueAt!.year}'),
                            onTap: _pickDueDate,
                          ),
                          const SizedBox(height: MiraiTokens.spaceSm),
                          TextButton(
                            onPressed: () => setState(() => _dueAt = null),
                            child: const Text('Ingen deadline - det är okej'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MiraiTokens.spaceLg,
            MiraiTokens.spaceSm,
            MiraiTokens.spaceLg,
            MiraiTokens.spaceLg,
          ),
          child: Row(
            children: [
              if (_currentStep == 1 && _dueAt == null) ...[
                OutlinedButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Hoppa'),
                ),
                const SizedBox(width: MiraiTokens.spaceSm),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: (_currentStep == 1 && !_saving) ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Spara läxa'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Efter sparande: OCR/text per bilaga, uppdaterar dokument stegvis (sammanslagen `extractedText`).
  Future<void> _runSequentialExtractions(String homeworkId, HomeworkItem seed) async {
    var hw = seed;
    final n = hw.attachments.length;
    for (var i = 0; i < n; i++) {
      try {
        final extracted = await _ai.extractFromAttachment(
          homeworkId,
          attachmentIndex: i,
        );
        hw = withAttachmentExtractApplied(hw, i, extracted.text);
        await widget.repository.update(hw);
      } catch (e) {
        debugPrint('[HomeworkCreate] extract idx $i failed: $e');
      }
    }
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({
    required this.label,
    required this.hint,
    required this.controller,
    this.onChanged,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MiraiTokens.bgRaised,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 3,
      decoration: BoxDecoration(
        color: active ? MiraiTokens.accent : MiraiTokens.bgInteractive,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _QuickDateCard extends StatelessWidget {
  const _QuickDateCard({
    required this.label,
    required this.date,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: selected ? MiraiTokens.accentSoft : MiraiTokens.bgRaised,
      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            border: Border.all(
              color: selected ? MiraiTokens.accentMuted : MiraiTokens.borderSubtle,
              width: MiraiTokens.borderThin,
            ),
          ),
          child: Column(
            children: [
              Text(label.toUpperCase(), style: tt.labelSmall?.copyWith(fontSize: 10, color: MiraiTokens.textTertiary)),
              const SizedBox(height: 2),
              Text('${date.day}/${date.month}', style: tt.bodySmall?.copyWith(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSameDay(DateTime? a, DateTime b) =>
    a != null && a.year == b.year && a.month == b.month && a.day == b.day;

String _guessMimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}
