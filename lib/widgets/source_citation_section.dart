import 'package:flutter/material.dart';

import '../theme/mirai_tokens.dart';

/// Kort källavsnitt kopplat till ett flashcard eller en testfråga (chunk X).
class SourceCitationSection extends StatelessWidget {
  const SourceCitationSection({
    super.key,
    required this.quote,
    this.dense = false,
  });

  final String quote;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final q = quote.trim();
    if (q.isEmpty) return const SizedBox.shrink();

    final tt = Theme.of(context).textTheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: dense ? EdgeInsets.zero : null,
        childrenPadding:
            dense ? EdgeInsets.zero : const EdgeInsets.only(bottom: MiraiTokens.spaceSm),
        title: Row(
          children: [
            Icon(
              Icons.format_quote_rounded,
              size: dense ? 18 : 20,
              color: MiraiTokens.accent.withValues(alpha: 0.9),
            ),
            const SizedBox(width: MiraiTokens.spaceXs),
            Text(
              'Källa ur materialet',
              style: (dense ? tt.labelMedium : tt.titleSmall)?.copyWith(
                fontWeight: FontWeight.w600,
                color: MiraiTokens.textSecondary,
              ),
            ),
          ],
        ),
        children: [
          SelectableText(
            '"$q"',
            style: tt.bodyMedium?.copyWith(
              height: 1.5,
              color: MiraiTokens.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
