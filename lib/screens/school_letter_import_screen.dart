import 'package:flutter/material.dart';

import '../data/local_homework_repository.dart';
import '../models/homework_item.dart';
import '../services/school_letter.dart';
import 'local_homework_form.dart';
import 'vardag_letter_picker.dart';

class SchoolLetterImportScreen extends StatefulWidget {
  const SchoolLetterImportScreen({
    super.key,
    required this.repository,
    required this.familyId,
    required this.uid,
    this.initialText = '',
  });
  final LocalHomeworkRepository repository;
  final String familyId, uid, initialText;

  @override
  State<SchoolLetterImportScreen> createState() => _SchoolLetterImportState();
}

class _SchoolLetterImportState extends State<SchoolLetterImportScreen> {
  late final _body = TextEditingController(text: widget.initialText);
  SchoolLetter? _source;
  List<HomeworkItem>? _drafts;
  final _selected = <String>{};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  void _preview(SchoolLetter letter) {
    final drafts = suggestHomework(
      letter,
      familyId: widget.familyId,
      uid: widget.uid,
      now: DateTime.now(),
    );
    FocusScope.of(context).unfocus();
    setState(() {
      _source = letter;
      _body.text = letter.text;
      _drafts = drafts;
      _selected
        ..clear()
        ..addAll(drafts.map((d) => d.id));
      _error = null;
    });
  }

  Future<void> _edit(HomeworkItem? draft) async {
    final now = DateTime.now();
    final base =
        draft ??
        HomeworkItem(
          id: 'egen-${now.microsecondsSinceEpoch}',
          familyId: widget.familyId,
          assignedToUserId: widget.uid,
          title: '',
          subject: '',
          topic: _source?.title,
          source: _source?.fromVardag == true ? 'vardag' : 'veckobrev',
          status: HomeworkStatus.todo,
          createdAt: now,
          updatedAt: now,
        );
    final edited = await Navigator.push<HomeworkItem>(
      context,
      MaterialPageRoute(
        builder: (_) => LocalHomeworkForm(
          initial: base,
          heading: draft == null ? 'Lägg till en läxa' : 'Granska läxan',
          saveLabel: 'Använd förslaget',
        ),
      ),
    );
    if (edited == null || !mounted) return;
    setState(() {
      if (draft == null) {
        final id = schoolDraftId(
          _source!,
          '${edited.subject} ${edited.title} ${edited.extractedText ?? ''}',
          widget.familyId,
          widget.uid,
        );
        if (!_drafts!.any((d) => d.id == id)) {
          _drafts!.add(edited.copyWith(id: id));
        }
        _selected.add(id);
      } else {
        _drafts![_drafts!.indexOf(draft)] = edited;
        _selected.add(edited.id);
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      final count = await widget.repository.importSelected(
        _drafts!.where((d) => _selected.contains(d.id)).toList(),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'De valda läxorna finns redan.'
                : count == 1
                ? 'En ny läxa har sparats.'
                : '$count nya läxor har sparats.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Det gick inte att spara. Dina val finns kvar här.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = _drafts;
    return Scaffold(
      appBar: AppBar(
        title: Text(drafts == null ? 'Veckobrev' : 'Granska läxorna'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (drafts == null) ...[
                  Text(
                    'Vilket brev vill du använda?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.inbox_outlined),
                    label: const Text('Hämta från Vardag'),
                    onPressed: () async {
                      final letter = await Navigator.push<SchoolLetter>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VardagLetterPicker(),
                        ),
                      );
                      if (letter != null && mounted) _preview(letter);
                    },
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _body,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 20000,
                    decoration: const InputDecoration(
                      labelText: 'Eller klistra in brevet',
                      alignLabelWithHint: true,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      if (_body.text.trim().isEmpty) {
                        setState(
                          () => _error = 'Klistra in brevets text först.',
                        );
                        return;
                      }
                      _preview(
                        SchoolLetter(
                          title: 'Inklistrat veckobrev',
                          text: _body.text.trim(),
                        ),
                      );
                    },
                    child: const Text('Hitta läxor'),
                  ),
                  TextButton(
                    onPressed: () => _preview(
                      const SchoolLetter(
                        title: 'Exempelbrev',
                        text: exampleSchoolLetter,
                      ),
                    ),
                    child: const Text('Prova med ett exempelbrev'),
                  ),
                ] else ...[
                  Text(
                    _source!.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    drafts.isEmpty
                        ? 'Inga tydliga läxor hittades. Läs brevet och lägg till en uppgift om du vill.'
                        : 'Välj läxor och kontrollera sista dag. Tryck på pennan för att ändra.',
                  ),
                  ExpansionTile(
                    title: const Text('Läs hela brevet'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(_source!.text),
                      ),
                    ],
                  ),
                  for (final d in drafts)
                    Card(
                      child: ListTile(
                        leading: Checkbox(
                          value: _selected.contains(d.id),
                          onChanged: _saving
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(d.id);
                                  } else {
                                    _selected.remove(d.id);
                                  }
                                }),
                        ),
                        title: Text(d.title),
                        subtitle: Text(
                          '${d.subject} · ${d.dueAt == null ? 'Inget datum valt' : '${d.dueAt!.day}/${d.dueAt!.month}'}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Ändra läxan',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _saving ? null : () => _edit(d),
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _saving ? null : () => _edit(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Lägg till en uppgift ur brevet'),
                  ),
                  FilledButton(
                    onPressed: _selected.isEmpty || _saving ? null : _save,
                    child: Text(
                      _saving ? 'Sparar…' : 'Spara valda (${_selected.length})',
                    ),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _drafts = null;
                            _source = null;
                            _error = null;
                          }),
                    child: const Text('Välj ett annat brev'),
                  ),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
