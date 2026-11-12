import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../data/homework_repository.dart';
import '../data/homework_storage_upload.dart';
import '../models/homework_attachment.dart';
import '../models/homework_item.dart';
import '../services/ai_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../util/merge_extracted_texts.dart';
import '../util/subject_suggestions.dart';
import '../widgets/subject_field.dart';

const _kMaxHomeworkAttachments = 8;

class _EditLocalPick {
  _EditLocalPick({required this.bytes, required this.fileName})
      : role = HomeworkAttachmentRole.mixed;
  final Uint8List bytes;
  final String fileName;
  HomeworkAttachmentRole role;
  String get mime => _guessMimeType(fileName);
}

class HomeworkEditScreen extends StatefulWidget {
  const HomeworkEditScreen({
    super.key,
    required this.repository,
    required this.familyId,
    required this.assignedToUserId,
    required this.initial,
  });

  final HomeworkRepository repository;
  final String familyId;
  final String assignedToUserId;
  final HomeworkItem? initial;

  @override
  State<HomeworkEditScreen> createState() => _HomeworkEditScreenState();
}

class _HomeworkEditScreenState extends State<HomeworkEditScreen> {
  final _titleCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _extractedCtrl = TextEditingController();
  final _ai = AiService();
  final _picker = ImagePicker();
  bool _saving = false;
  bool _aiBusy = false;
  DateTime? _dueAt;
  HomeworkStatus _status = HomeworkStatus.todo;
  final List<_EditLocalPick> _pendingLocalAdds = [];

  /// Radrad extrakt (sparad vid nästa [_save]); `null` = använd befintlig [HomeworkItem.attachments].
  List<HomeworkAttachment>? _pendingExtractAttachments;

  @override
  void initState() {
    super.initState();
    final h = widget.initial;
    _titleCtrl.text = h?.title ?? '';
    _subjectCtrl.text = h?.subject ?? '';
    _summaryCtrl.text = h?.summary ?? '';
    _extractedCtrl.text = h?.extractedText ?? '';
    _dueAt = h?.dueAt;
    _status = h?.status ?? HomeworkStatus.todo;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subjectCtrl.dispose();
    _summaryCtrl.dispose();
    _extractedCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final r =
        await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    if (r == null || r.files.isEmpty) return;
    var hitLimit = false;
    setState(() {
      _pendingExtractAttachments = null;
      for (final f in r.files) {
        if (_pendingLocalAdds.length >= _kMaxHomeworkAttachments) {
          hitLimit = true;
          break;
        }
        if (f.bytes != null && f.name.trim().isNotEmpty) {
          _pendingLocalAdds.add(
            _EditLocalPick(bytes: f.bytes!, fileName: f.name),
          );
        }
      }
    });
    if (hitLimit && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Max $_kMaxHomeworkAttachments bilagor — några hoppades över.'),
        ),
      );
    }
  }

  Future<void> _pickPhoto() async {
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
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (_pendingLocalAdds.length >= _kMaxHomeworkAttachments) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Max $_kMaxHomeworkAttachments bilagor.')),
        );
      }
      return;
    }
    final image = await _picker.pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 95,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingExtractAttachments = null;
      _pendingLocalAdds.add(_EditLocalPick(bytes: bytes, fileName: image.name));
    });
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      initialDate: _dueAt ?? DateTime.now(),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final base = widget.initial;
      final now = DateTime.now();
      HomeworkItem item = (base ??
              HomeworkItem(
                id: '',
                familyId: widget.familyId,
                assignedToUserId: widget.assignedToUserId,
                subject: _subjectCtrl.text.trim().isEmpty ? 'Ämne' : _subjectCtrl.text.trim(),
                title: title,
                dueAt: _dueAt,
                status: _status,
                summary: _summaryCtrl.text.trim().isEmpty ? null : _summaryCtrl.text.trim(),
                extractedText: _extractedCtrl.text.trim().isEmpty ? null : _extractedCtrl.text.trim(),
                createdAt: now,
                updatedAt: now,
              ))
          .copyWith(
            title: title,
            subject: _subjectCtrl.text.trim().isEmpty ? 'Ämne' : _subjectCtrl.text.trim(),
            dueAt: _dueAt,
            status: _status,
            summary: _summaryCtrl.text.trim().isEmpty ? null : _summaryCtrl.text.trim(),
            extractedText: _extractedCtrl.text.trim().isEmpty ? null : _extractedCtrl.text.trim(),
          );

      if (base == null) {
        final id = await widget.repository.create(item);
        item = item.copyWith(id: id);
      }

      var attachmentsList = _pendingExtractAttachments != null
          ? List<HomeworkAttachment>.from(_pendingExtractAttachments!)
          : (widget.initial != null
              ? List<HomeworkAttachment>.from(attachmentsOrLegacySynthetic(widget.initial!))
              : <HomeworkAttachment>[]);

      if (_pendingLocalAdds.isNotEmpty) {
        for (final p in _pendingLocalAdds) {
          final url = await uploadHomeworkAttachmentBytes(
            familyId: widget.familyId,
            homeworkId: item.id,
            fileName: p.fileName,
            bytes: p.bytes,
            contentType: p.mime,
          );
          final mt = p.mime.trim().isEmpty ? 'application/octet-stream' : p.mime.trim();
          attachmentsList.add(
            HomeworkAttachment(
              fileName: p.fileName,
              mimeType: mt,
              storageUrl: url,
              extractedText: null,
              addedAt: now,
              role: p.role,
            ),
          );
        }
      }

      if (attachmentsList.isNotEmpty) {
        final prim = attachmentsList.first;
        item = item.copyWith(
          attachments: attachmentsList,
          attachmentStorageUrl: prim.storageUrl,
          attachmentFileName: prim.fileName,
          attachmentMimeType: prim.mimeType,
        );
      } else {
        item = item.copyWith(attachments: attachmentsList);
      }

      await widget.repository.update(item);
      if (!mounted) return;
      Navigator.of(context).pop();
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

  Future<void> _extractAttachment() async {
    final base = widget.initial;
    final id = base?.id;
    if (id == null || base == null) return;

    final rows = attachmentsOrLegacySynthetic(base);
    if (rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Läxan har ingen bilaga att läsa.')),
      );
      return;
    }
    var attachmentIndex = 0;
    if (rows.length > 1) {
      if (!mounted) return;
      final picked = await showModalBottomSheet<int>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows.length; i++)
                ListTile(
                  title: Text(
                    rows[i].fileName.trim().isEmpty
                        ? 'Bilaga ${i + 1}'
                        : rows[i].fileName,
                  ),
                  onTap: () => Navigator.of(ctx).pop(i),
                ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      attachmentIndex = picked;
    }

    setState(() => _aiBusy = true);
    try {
      final result = await _ai.extractFromAttachment(
        id,
        attachmentIndex: attachmentIndex,
      );
      final merged =
          withAttachmentExtractApplied(base, attachmentIndex, result.text);
      if (!mounted) return;
      setState(() {
        _extractedCtrl.text = merged.extractedText ?? result.text;
        _pendingExtractAttachments = merged.attachments;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text extraherad')),
      );
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att extrahera texten. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _generateSummary() async {
    final text = _extractedCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final summary = await _ai.summarize(text);
      if (!mounted) return;
      setState(() => _summaryCtrl.text = summary);
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att skapa sammanfattningen. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isLocalOnlyDemo =
        kUseFirestoreHomework && (widget.initial?.id.startsWith('dev-') ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('Redigera läxa')),
      body: SafeArea(
        child: Center(
          child: MiraiAdaptiveBox(
            child: ListView(
              padding: const EdgeInsets.all(MiraiTokens.spaceLg),
              children: [
                if (isLocalOnlyDemo) ...[
                  Container(
                    padding: const EdgeInsets.all(MiraiTokens.spaceSm),
                    decoration: BoxDecoration(
                      color: MiraiTokens.bgRaised,
                      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                      border: Border.all(
                        color: MiraiTokens.warning,
                        width: MiraiTokens.borderThin,
                      ),
                    ),
                    child: Text(
                      'Den här läxan finns bara lokalt (gammal demo-data). Skapa en ny.',
                      style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
                    ),
                  ),
                  const SizedBox(height: MiraiTokens.spaceLg),
                ],
                _Section(title: 'GRUND', child: Column(children: [
                  _Field(controller: _titleCtrl, label: 'Titel'),
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
                        label: 'Ämne',
                        denseBox: false,
                      );
                    },
                  ),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  OutlinedButton.icon(
                    onPressed: _pickDue,
                    icon: const Icon(Icons.event_rounded),
                    label: Text(_dueAt == null ? 'Ingen deadline' : '${_dueAt!.day}/${_dueAt!.month}/${_dueAt!.year}'),
                  ),
                ])),
                _Section(title: 'MATERIAL', child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: MiraiTokens.spaceSm,
                      children: [
                        OutlinedButton.icon(
                          onPressed: (_saving || _aiBusy) ? null : _pickPhoto,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Foto'),
                        ),
                        OutlinedButton.icon(
                          onPressed: (_saving || _aiBusy) ? null : _pickDocument,
                          icon: const Icon(Icons.attach_file_rounded),
                          label: const Text('Fil(er)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: (_saving || _aiBusy || widget.initial == null || isLocalOnlyDemo)
                              ? null
                              : _extractAttachment,
                          icon: const Icon(Icons.text_snippet_outlined),
                          label: const Text('Extrahera text'),
                        ),
                        if (isLocalOnlyDemo)
                          const Tooltip(
                            message: 'Den här läxan är inte sparad i molnet',
                            child: Icon(Icons.info_outline_rounded, size: 16),
                          ),
                      ],
                    ),
                    if (widget.initial != null &&
                        attachmentsOrLegacySynthetic(widget.initial!).isNotEmpty) ...[
                      Text(
                        'Sparade källor',
                        style: tt.labelSmall?.copyWith(
                          letterSpacing: 0.5,
                          color: MiraiTokens.textTertiary,
                        ),
                      ),
                      const SizedBox(height: MiraiTokens.spaceXs),
                      for (final a in attachmentsOrLegacySynthetic(widget.initial!))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.insert_drive_file_outlined,
                            size: 20,
                            color: MiraiTokens.textSecondary,
                          ),
                          title: Text(
                            a.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall,
                          ),
                          subtitle: Text(
                            '${a.role.labelSv} · '
                            '${(a.extractedText ?? '').trim().isNotEmpty ? "Extraherad text finns" : "Ej extraherad"}',
                            style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                          ),
                        ),
                      const SizedBox(height: MiraiTokens.spaceSm),
                    ],
                    if (_pendingLocalAdds.isNotEmpty) ...[
                      Text(
                        'Nya filer (laddas upp vid Spara)',
                        style: tt.labelSmall?.copyWith(
                          letterSpacing: 0.5,
                          color: MiraiTokens.textTertiary,
                        ),
                      ),
                      for (var i = 0; i < _pendingLocalAdds.length; i++)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.upload_file_rounded,
                            size: 20,
                            color: MiraiTokens.textSecondary,
                          ),
                          title: Text(
                            _pendingLocalAdds[i].fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall,
                          ),
                          subtitle: Text(
                            _pendingLocalAdds[i].role.labelSv,
                            style: tt.bodySmall?.copyWith(color: MiraiTokens.accent),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<HomeworkAttachmentRole>(
                                tooltip: 'Roll',
                                icon: Icon(
                                  Icons.tune_rounded,
                                  size: 20,
                                  color: MiraiTokens.textSecondary,
                                ),
                                onSelected: (r) => setState(
                                  () => _pendingLocalAdds[i].role = r,
                                ),
                                itemBuilder: (ctx) => [
                                  for (final r in HomeworkAttachmentRole.values)
                                    PopupMenuItem(
                                      value: r,
                                      child: Text(r.labelSv),
                                    ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: _saving
                                    ? null
                                    : () => setState(
                                          () => _pendingLocalAdds.removeAt(i),
                                        ),
                                tooltip: 'Ta bort',
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: MiraiTokens.spaceSm),
                    ],
                    const SizedBox(height: MiraiTokens.spaceSm),
                    _Field(
                      controller: _extractedCtrl,
                      label: 'Extraherad text',
                      minLines: 6,
                      maxLines: 10,
                    ),
                  ],
                )),
                _Section(title: 'AI', child: Column(
                  children: [
                    _Field(
                      controller: _summaryCtrl,
                      label: 'Sammanfattning',
                      minLines: 5,
                      maxLines: 8,
                    ),
                    const SizedBox(height: MiraiTokens.spaceSm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: isLocalOnlyDemo
                          ? Tooltip(
                              message: 'Den här läxan är inte sparad i molnet',
                              child: OutlinedButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.auto_awesome),
                                label: const Text('Generera'),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: (_saving || _aiBusy) ? null : _generateSummary,
                              icon: _aiBusy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.auto_awesome),
                              label: const Text('Generera'),
                            ),
                    ),
                  ],
                )),
                _Section(title: 'STATUS', child: DropdownButtonFormField<HomeworkStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: HomeworkStatus.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.labelSv)))
                      .toList(),
                  onChanged: (v) => setState(() => _status = v ?? HomeworkStatus.todo),
                )),
                const SizedBox(height: 100),
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
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Ångra'),
                ),
              ),
              const SizedBox(width: MiraiTokens.spaceSm),
              Expanded(
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
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: MiraiTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tt.labelSmall?.copyWith(
              letterSpacing: 0.5,
              color: MiraiTokens.textTertiary,
            ),
          ),
          const SizedBox(height: MiraiTokens.spaceSm),
          child,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.minLines,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String label;
  final int? minLines;
  final int maxLines;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    );
  }
}

String _guessMimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}
