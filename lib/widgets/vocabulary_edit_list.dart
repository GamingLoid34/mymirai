import 'package:flutter/material.dart';

import '../models/vocabulary_entry.dart';
import '../theme/mirai_tokens.dart';

/// Redigeringsvy för gloslistor innan eller efter att kort genererats (AP5).
class VocabularyEditList extends StatefulWidget {
  const VocabularyEditList({
    super.key,
    required this.initialEntries,
    required this.onSaved,
    required this.onCancel,
  });

  final List<VocabularyEntry> initialEntries;
  final ValueChanged<List<VocabularyEntry>> onSaved;
  final VoidCallback onCancel;

  @override
  State<VocabularyEditList> createState() => _VocabularyEditListState();
}

class _EditableEntry {
  _EditableEntry({
    required String term,
    required String translation,
    this.example,
  })  : termCtrl = TextEditingController(text: term),
        transCtrl = TextEditingController(text: translation);

  final TextEditingController termCtrl;
  final TextEditingController transCtrl;
  String? example;

  void dispose() {
    termCtrl.dispose();
    transCtrl.dispose();
  }
}

class _VocabularyEditListState extends State<VocabularyEditList> {
  final List<_EditableEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialEntries.isEmpty) {
      _entries.add(_EditableEntry(term: '', translation: ''));
    } else {
      for (final e in widget.initialEntries) {
        _entries.add(
          _EditableEntry(
            term: e.term,
            translation: e.translation,
            example: e.example,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  void _addEntry() {
    setState(() {
      _entries.add(_EditableEntry(term: '', translation: ''));
    });
  }

  void _removeEntry(int index) {
    setState(() {
      final removed = _entries.removeAt(index);
      removed.dispose();
    });
  }

  void _save() {
    final result = <VocabularyEntry>[];
    for (final e in _entries) {
      final term = e.termCtrl.text.trim();
      final trans = e.transCtrl.text.trim();
      if (term.isNotEmpty || trans.isNotEmpty) {
        result.add(
          VocabularyEntry(
            term: term,
            translation: trans,
            example: e.example,
          ),
        );
      }
    }
    widget.onSaved(result);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MiraiTokens.bgRaised,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        border: Border.all(
          color: MiraiTokens.borderSubtle,
          width: MiraiTokens.borderThin,
        ),
      ),
      padding: const EdgeInsets.all(MiraiTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'RÄTTA GLOSOR',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.5,
                      color: MiraiTokens.textTertiary,
                    ),
              ),
              const Spacer(),
              Text(
                '${_entries.length} st',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: MiraiTokens.textTertiary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: MiraiTokens.spaceSm),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _entries.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 16, color: MiraiTokens.borderSubtle),
            itemBuilder: (context, index) {
              final entry = _entries[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: entry.termCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ord / fras',
                        hintText: 'T.ex. dog',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: MiraiTokens.spaceSm),
                  Expanded(
                    child: TextFormField(
                      controller: entry.transCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Översättning',
                        hintText: 'T.ex. hund',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: MiraiTokens.textTertiary,
                      size: 20,
                    ),
                    tooltip: 'Ta bort',
                    onPressed: _entries.length > 1
                        ? () => _removeEntry(index)
                        : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
          OutlinedButton.icon(
            onPressed: _addEntry,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Lägg till glosa'),
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Avbryt'),
              ),
              const SizedBox(width: MiraiTokens.spaceSm),
              FilledButton(
                onPressed: _save,
                child: const Text('Spara glosor'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
