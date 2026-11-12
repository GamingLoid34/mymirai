import 'package:flutter/material.dart';

import '../data/local_homework_repository.dart';
import '../models/homework_item.dart';
import '../services/local_practice.dart';
import '../widgets/tts_player_sheet.dart';
import 'local_homework_form.dart';

class LocalHomeworkLesson extends StatefulWidget {
  const LocalHomeworkLesson({
    super.key,
    required this.item,
    required this.repository,
  });
  final HomeworkItem item;
  final LocalHomeworkRepository repository;
  @override
  State<LocalHomeworkLesson> createState() => _LocalHomeworkLessonState();
}

class _LocalHomeworkLessonState extends State<LocalHomeworkLesson> {
  final _answer = TextEditingController();
  bool _hint = false,
      _reveal = false,
      _correct = false,
      _wrong = false,
      _busy = false;
  String? _error;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _clearAnswer() {
    _answer.clear();
    _hint = false;
    _reveal = false;
    _correct = false;
    _wrong = false;
  }

  Future<void> _update(HomeworkItem next) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.update(next);
      if (mounted) setState(_clearAnswer);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Framsteget kunde inte sparas. Försök igen.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final exercises = practiceFor(item);
    final completed = item.steps.where((s) => s.done).map((s) => s.id).toSet();
    final index = exercises.indexWhere((e) => !completed.contains(e.id));
    final exercise = index < 0 ? null : exercises[index];
    final done = item.status == HomeworkStatus.done;
    final material = (item.extractedText ?? '').trim();
    final due = item.dueAt;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Min läxa'),
        actions: [
          IconButton(
            tooltip: 'Ändra läxan',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _busy
                ? null
                : () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LocalHomeworkForm(
                          initial: item,
                          heading: 'Ändra läxan',
                          onSave: widget.repository.update,
                        ),
                      ),
                    );
                    if (mounted) setState(_clearAnswer);
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  [
                    item.subject,
                    if (due != null) 'Till ${due.day}/${due.month}',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (item.topic?.isNotEmpty == true)
                  Text(
                    item.topic!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (material.isNotEmpty &&
                    material != item.title &&
                    material != '${item.subject}: ${item.title}')
                  if (exercise?.answer != null)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Visa hela uppgiften'),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(material),
                        ),
                      ],
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(material),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.volume_up_outlined),
                    label: const Text('Lyssna på uppgiften'),
                    onPressed: () => showTtsPlayer(
                      context,
                      text: material.isEmpty ? item.title : material,
                      title: item.title,
                      subject: item.subject,
                    ),
                  ),
                ),
                const Divider(),
                if (!done && exercise != null) ...[
                  Text(
                    'Öva · steg ${index + 1} av ${exercises.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    exercise.prompt,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _hint = !_hint),
                      child: Text(_hint ? 'Dölj ledtråden' : 'Visa ledtråd'),
                    ),
                  ),
                  if (_hint)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(exercise.hint),
                    ),
                  if (exercise.answer != null) ...[
                    TextField(
                      controller: _answer,
                      decoration: const InputDecoration(labelText: 'Ditt svar'),
                      onChanged: (_) => setState(() {
                        _correct = false;
                        _wrong = false;
                      }),
                      onSubmitted: (v) => setState(() {
                        _correct = exercise.matches(v);
                        _wrong = !_correct;
                      }),
                    ),
                    const SizedBox(height: 8),
                    if (_correct)
                      Semantics(
                        liveRegion: true,
                        child: const Text('Rätt svar!'),
                      )
                    else if (_wrong)
                      Semantics(
                        liveRegion: true,
                        child: const Text('Försök igen. Du kan ta en ledtråd.'),
                      ),
                    if (_reveal) Text('Svar: ${exercise.answer}'),
                    if (!_correct && !_reveal)
                      Wrap(
                        children: [
                          OutlinedButton(
                            onPressed: _answer.text.trim().isEmpty
                                ? null
                                : () => setState(() {
                                    _correct = exercise.matches(_answer.text);
                                    _wrong = !_correct;
                                  }),
                            child: const Text('Kolla svaret'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _reveal = true),
                            child: const Text('Visa svaret'),
                          ),
                        ],
                      ),
                  ],
                  if (exercise.answer == null || _correct || _reveal)
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _update(
                              item.copyWith(
                                status: HomeworkStatus.inProgress,
                                steps: [
                                  ...item.steps.where(
                                    (s) => s.id != exercise.id,
                                  ),
                                  HomeworkStep(
                                    id: exercise.id,
                                    label: exercise.prompt,
                                    done: true,
                                  ),
                                ],
                              ),
                            ),
                      child: Text(
                        exercise.answer == null
                            ? 'Jag har gjort steget'
                            : 'Nästa steg',
                      ),
                    ),
                ] else if (!done) ...[
                  Text(
                    'Du har övat klart!',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _update(item.copyWith(steps: [])),
                    child: const Text('Öva en gång till'),
                  ),
                ],
                const SizedBox(height: 16),
                if (done) const Text('Läxan är klar.'),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _update(
                          item.copyWith(
                            status: done
                                ? HomeworkStatus.inProgress
                                : HomeworkStatus.done,
                          ),
                        ),
                  icon: Icon(done ? Icons.undo : Icons.check),
                  label: Text(done ? 'Öppna läxan igen' : 'Markera läxan klar'),
                ),
                if (_error != null) Text(_error!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
