import 'package:flutter/material.dart';

import '../models/homework_item.dart';

/// Samma fält används för handskrivna läxor och förslag från ett veckobrev.
class LocalHomeworkForm extends StatefulWidget {
  const LocalHomeworkForm({
    super.key,
    required this.initial,
    required this.heading,
    this.onSave,
    this.saveLabel = 'Spara läxan',
  });
  final HomeworkItem initial;
  final String heading;
  final String saveLabel;
  final Future<void> Function(HomeworkItem)? onSave;

  @override
  State<LocalHomeworkForm> createState() => _LocalHomeworkFormState();
}

class _LocalHomeworkFormState extends State<LocalHomeworkForm> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _subject = TextEditingController(text: widget.initial.subject);
  late final _body = TextEditingController(
    text: widget.initial.extractedText ?? widget.initial.details ?? '',
  );
  late DateTime? _due = widget.initial.dueAt;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Ge läxan en rubrik.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final updated = widget.initial.copyWith(
      title: _title.text.trim(),
      subject: _subject.text.trim().isEmpty ? 'Övrigt' : _subject.text.trim(),
      extractedText: _body.text.trim(),
      dueAt: _due,
      clearDueAt: _due == null,
    );
    try {
      await widget.onSave?.call(updated);
      if (!mounted) return;
      if (widget.onSave == null) {
        Navigator.pop(context, updated);
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Läxan kunde inte sparas. Försök igen.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.heading)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Rubrik'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subject,
                decoration: const InputDecoration(labelText: 'Ämne'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _body,
                minLines: 3,
                maxLines: 9,
                decoration: const InputDecoration(
                  labelText: 'Uppgift och material',
                  hintText:
                      'Vad ska du göra? Klistra gärna in text, räknetal eller glospar.',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(
                  _due == null
                      ? 'Välj sista dag'
                      : '${_due!.day}/${_due!.month} ${_due!.year}',
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _due ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2200),
                  );
                  if (date != null && mounted) setState(() => _due = date);
                },
                trailing: _due == null
                    ? null
                    : IconButton(
                        tooltip: 'Ta bort datum',
                        onPressed: () => setState(() => _due = null),
                        icon: const Icon(Icons.close),
                      ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(widget.saveLabel),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
