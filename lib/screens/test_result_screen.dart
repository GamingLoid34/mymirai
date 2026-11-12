import 'package:flutter/material.dart';

import '../data/deck_repository.dart';
import '../data/xp_repository.dart';
import '../models/flashcard.dart';
import '../models/test_question_item.dart';
import '../services/xp_rules.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../widgets/celebration.dart';
import '../widgets/xp_chip.dart';
import 'quiz_session_screen.dart';

/// Ett avslutat test (ingen lagring i Firestore).
class TestOutcome {
  const TestOutcome({
    required this.question,
    required this.card,
    required this.verdict,
    required this.feedback,
  });

  final TestQuestionItem question;
  final Flashcard card;
  final String verdict;
  final String feedback;
}

class TestResultScreen extends StatefulWidget {
  const TestResultScreen({
    super.key,
    required this.deckRepository,
    required this.outcomes,
    this.subjectByDeckId,
    this.xpRepository,
    this.uid,
  });

  final DeckRepository deckRepository;
  final List<TestOutcome> outcomes;
  final Map<String, String>? subjectByDeckId;
  final XpRepository? xpRepository;
  final String? uid;

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  DeckRepository get deckRepository => widget.deckRepository;
  List<TestOutcome> get outcomes => widget.outcomes;
  Map<String, String>? get subjectByDeckId => widget.subjectByDeckId;

  double get _score01 {
    if (outcomes.isEmpty) return 0;
    var sum = 0.0;
    for (final o in outcomes) {
      switch (o.verdict) {
        case 'correct':
          sum += 1;
          break;
        case 'partial':
          sum += 0.5;
          break;
        default:
          break;
      }
    }
    return sum / outcomes.length;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Celebration.show(context, size: CelebrationSize.medium);
      final xp = widget.xpRepository;
      final uid = widget.uid;
      if (xp != null && uid != null) {
        xp.addXp(uid, XpRules.testDone);
        XpChip.show(context, XpRules.testDone);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pct = (_score01 * 100).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Provresultat')),
      body: SafeArea(
        child: Center(
          child: MiraiAdaptiveBox(
            child: ListView(
              padding: const EdgeInsets.all(MiraiTokens.spaceLg),
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: pct / 100,
                            strokeWidth: 8,
                            backgroundColor: MiraiTokens.borderSubtle,
                            color: MiraiTokens.accent,
                          ),
                          Center(
                            child: Text(
                              '$pct%',
                              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: MiraiTokens.spaceLg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pct >= 80 ? 'Wow – riktigt starkt!' : 'Bra kämpat! Vill du gå igenom de kluriga?',
                            style: tt.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${outcomes.where((o) => o.verdict == 'correct').length} rätt · '
                            '${outcomes.where((o) => o.verdict == 'partial').length} delvis · '
                            '${outcomes.where((o) => o.verdict == 'wrong').length} fel',
                            style: tt.bodyMedium?.copyWith(color: MiraiTokens.textSecondary),
                          ),
                          if (subjectByDeckId != null && subjectByDeckId!.length > 1) ...[
                            const SizedBox(height: MiraiTokens.spaceSm),
                            Text(
                              'Flera lekar i samma prov',
                              style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MiraiTokens.spaceLg),
                Text('Gå igenom', style: tt.titleMedium),
                const SizedBox(height: MiraiTokens.spaceSm),
                for (var i = 0; i < outcomes.length; i++) ...[
                  _OutcomeTile(
                    indexLabel: '${i + 1}',
                    outcome: outcomes[i],
                    subjectLabel: subjectByDeckId?[outcomes[i].card.deckId],
                  ),
                  const SizedBox(height: MiraiTokens.spaceSm),
                ],
                const SizedBox(height: MiraiTokens.spaceMd),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final hard = outcomes
                          .where(
                            (o) => o.verdict == 'wrong' || o.verdict == 'partial',
                          )
                          .map((o) => o.card)
                          .toList(growable: false);
                      if (!context.mounted) return;
                      if (hard.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Du hade inga fel att plugga vidare på.')),
                        );
                        return;
                      }
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => QuizSessionScreen(
                            deckRepository: deckRepository,
                            cards: hard,
                            deck: null,
                            subjectByDeckId: subjectByDeckId,
                            examDeckCount: hard.map((c) => c.deckId).toSet().length,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.lightbulb_outline_rounded),
                    label: const Text('Plugga om de svåra'),
                  ),
                ),
                const SizedBox(height: MiraiTokens.spaceSm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    child: const Text('Klar'),
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

class _OutcomeTile extends StatelessWidget {
  const _OutcomeTile({
    required this.indexLabel,
    required this.outcome,
    this.subjectLabel,
  });

  final String indexLabel;
  final TestOutcome outcome;
  final String? subjectLabel;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final v = outcome.verdict;
    final isCorrect = v == 'correct';
    final isPartial = v == 'partial';
    final bg = isCorrect
        ? MiraiTokens.success.withValues(alpha: 0.12)
        : isPartial
            ? MiraiTokens.warning.withValues(alpha: 0.12)
            : MiraiTokens.danger.withValues(alpha: 0.12);
    final badge = isCorrect ? 'Rätt' : (isPartial ? 'Delvis' : 'Fel');
    return Container(
      padding: const EdgeInsets.all(MiraiTokens.spaceMd),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        border: Border.all(color: MiraiTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                indexLabel,
                style: tt.labelLarge?.copyWith(color: MiraiTokens.textTertiary),
              ),
              const SizedBox(width: MiraiTokens.spaceSm),
              Expanded(
                child: Text(
                  outcome.question.front,
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: MiraiTokens.spaceSm),
              Text(
                badge,
                style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (subjectLabel != null && subjectLabel!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subjectLabel!.trim(),
              style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
            ),
          ],
          const SizedBox(height: MiraiTokens.spaceSm),
          Text(outcome.feedback, style: tt.bodyMedium),
          if (!isCorrect || isPartial) ...[
            const SizedBox(height: MiraiTokens.spaceSm),
            Text(
              'Facit (kortet): ${outcome.card.back}',
              style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
