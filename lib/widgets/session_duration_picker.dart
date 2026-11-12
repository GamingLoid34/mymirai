import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/mirai_tokens.dart';

const _kPrefSessionDurationMinutes = 'session_duration_minutes';

/// `null` betyder "Tills korten är slut" (ingen timer).
Future<int?> showSessionDurationPicker(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return null;
  final last = prefs.getInt(_kPrefSessionDurationMinutes) ?? 10;

  final choice = await showModalBottomSheet<int?>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MiraiTokens.spaceLg,
          MiraiTokens.spaceSm,
          MiraiTokens.spaceLg,
          MiraiTokens.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hur länge?', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: MiraiTokens.spaceMd),
            Wrap(
              spacing: MiraiTokens.spaceSm,
              runSpacing: MiraiTokens.spaceSm,
              children: [
                _DurationChip(label: '5 min', selected: last == 5, onTap: () => Navigator.of(ctx).pop(5)),
                _DurationChip(label: '10 min', selected: last == 10, onTap: () => Navigator.of(ctx).pop(10)),
                _DurationChip(
                  label: 'Tills korten är slut',
                  selected: last == 0,
                  onTap: () => Navigator.of(ctx).pop(0),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (choice == null) return null;
  await prefs.setInt(_kPrefSessionDurationMinutes, choice);
  return choice == 0 ? null : choice;
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
