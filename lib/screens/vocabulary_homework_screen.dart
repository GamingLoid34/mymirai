import 'package:flutter/material.dart';

import '../config.dart';
import '../data/deck_repository.dart';
import '../data/homework_repository.dart';
import '../models/homework_item.dart';
import '../models/vocabulary_entry.dart';
import '../services/ai_service.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../util/subject_suggestions.dart';
import '../widgets/subject_field.dart';
import 'homework_detail_screen.dart';

/// Skapa glosläxa: klistra in text, parsa med AI, spara som `homeworkType: vocabulary`.
class VocabularyHomeworkScreen extends StatefulWidget {
  const VocabularyHomeworkScreen({
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
  State<VocabularyHomeworkScreen> createState() => _VocabularyHomeworkScreenState();
}

class _VocabularyHomeworkScreenState extends State<VocabularyHomeworkScreen> {
  final _titleCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _rawCtrl = TextEditingController();
  final _ai = AiService();
  List<VocabularyEntry> _parsed = [];
  bool _busy = false;
  bool _saving = false;
  DateTime? _dueAt;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subjectCtrl.dispose();
    _rawCtrl.dispose();
    super.dispose();
  }

  Future<void> _runParse() async {
    final raw = _rawCtrl.text.trim();
    if (raw.length < 3 || _busy) return;
    setState(() => _busy = true);
    try {
      final list = await _ai.parseVocabulary(rawText: raw);
      if (!mounted) return;
      setState(() => _parsed = list);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${list.length} glos-par hittades')),
      );
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att tolka glosorna. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_parsed.isEmpty ||
        _titleCtrl.text.trim().isEmpty ||
        _saving) {
      if (_parsed.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parsa gloslistan först')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      var draft = HomeworkItem(
        id: '',
        familyId: widget.familyId,
        assignedToUserId: widget.assignedToUserId,
        subject: _subjectCtrl.text.trim().isEmpty ? 'Språk' : _subjectCtrl.text.trim(),
        title: _titleCtrl.text.trim(),
        dueAt: _dueAt,
        status: HomeworkStatus.todo,
        homeworkType: 'vocabulary',
        vocabulary: _parsed,
        mathProblems: const [],
        createdAt: now,
        updatedAt: now,
      );
      final id = await widget.repository.create(draft);
      if (!mounted) return;
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
      setState(() => _saving = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara läxan. Testa igen om en stund.',
        error: e,
      );
    }
  }

  Future<void> _pickDue() async {
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
      appBar: AppBar(
        title: const Text('Ny glosläxa'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(MiraiTokens.spaceLg),
          children: [
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
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
                  hint: 'T.ex. Engelska',
                );
              },
            ),
            const SizedBox(height: MiraiTokens.spaceSm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickDue,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _dueAt == null
                      ? 'Deadline (valfritt)'
                      : 'Deadline: ${_dueAt!.day}/${_dueAt!.month}',
                ),
              ),
            ),
            const SizedBox(height: MiraiTokens.spaceMd),
            Text(
              'Klista in glosor (hur som helst formaterade)',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: MiraiTokens.spaceSm),
            TextField(
              controller: _rawCtrl,
              minLines: 6,
              maxLines: 14,
              decoration: const InputDecoration(
                hintText:
                    't.ex. hello : hej\\ncat — katt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: MiraiTokens.spaceMd),
            FilledButton.icon(
              onPressed: _busy ? null : _runParse,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_outlined),
              label: Text(_busy ? 'Parsar…' : 'Parsa med AI'),
            ),
            if (_parsed.isNotEmpty) ...[
              const SizedBox(height: MiraiTokens.spaceLg),
              Text(
                'FÖREGRANSKNING (${_parsed.length} par)',
                style: tt.labelSmall?.copyWith(color: MiraiTokens.textTertiary),
              ),
              const SizedBox(height: MiraiTokens.spaceSm),
              Container(
                decoration: BoxDecoration(
                  color: MiraiTokens.bgRaised,
                  borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                  border: Border.all(color: MiraiTokens.borderSubtle),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _parsed.length.clamp(0, 60),
                  separatorBuilder: (_, unusedIndex) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final e = _parsed[i];
                    return ListTile(
                      dense: true,
                      title: Text(e.term, style: tt.bodyMedium),
                      subtitle: Text(e.translation, style: tt.bodySmall),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: MiraiTokens.spaceXl),
            FilledButton(
              onPressed: (_saving || _parsed.isEmpty) ? null : _save,
              child: Text(_saving ? 'Sparar…' : 'Spara glosläxa'),
            ),
          ],
        ),
      ),
    );
  }
}
