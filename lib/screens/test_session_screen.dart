import 'package:flutter/material.dart';

import '../data/deck_repository.dart';
import '../data/xp_repository.dart';
import '../models/flashcard.dart';
import '../models/test_question_item.dart';
import '../services/ai_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../widgets/source_citation_section.dart';
import 'test_result_screen.dart';

class TestSessionScreen extends StatefulWidget {
  const TestSessionScreen({
    super.key,
    required this.deckRepository,
    required this.questions,
    required this.cardsById,
    this.subjectByDeckId,
    this.xpRepository,
    this.uid,
  });

  final DeckRepository deckRepository;
  final List<TestQuestionItem> questions;
  final Map<String, Flashcard> cardsById;
  final Map<String, String>? subjectByDeckId;
  final XpRepository? xpRepository;
  final String? uid;

  @override
  State<TestSessionScreen> createState() => _TestSessionScreenState();
}

class _TestSessionScreenState extends State<TestSessionScreen> {
  final _ai = AiService();
  final _openAnswerCtrl = TextEditingController();
  int _idx = 0;
  bool _grading = false;
  String _gradeStatus = '';

  final Map<String, String> _openDraft = {};
  final Map<String, int> _mcChoice = {};

  TestQuestionItem get _q => widget.questions[_idx];

  @override
  void initState() {
    super.initState();
    _applyQuestionToControllers();
  }

  @override
  void dispose() {
    _openAnswerCtrl.dispose();
    super.dispose();
  }

  void _applyQuestionToControllers() {
    final q = _q;
    if (q.type == TestQuestionType.open) {
      _openAnswerCtrl.text = _openDraft[q.cardId] ?? '';
    }
  }

  void _persistOpenFromField() {
    final q = _q;
    if (q.type == TestQuestionType.open) {
      _openDraft[q.cardId] = _openAnswerCtrl.text;
    }
  }

  Future<bool?> _confirmLeave() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lämna provet?'),
        content: const Text('Dina svar på denna sida sparas inte om du lämnar nu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Fortsätt')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lämna')),
        ],
      ),
    );
  }

  Future<bool> _maybePopRoute() async {
    if (_grading) return false;
    final leave = await _confirmLeave();
    if (!mounted) return false;
    if (leave == true) {
      Navigator.of(context).pop();
      return true;
    }
    return false;
  }

  bool _canAdvance() {
    final q = _q;
    if (q.type == TestQuestionType.multipleChoice) {
      return _mcChoice.containsKey(q.cardId);
    }
    final t = _openAnswerCtrl.text.trim();
    return t.length >= 3;
  }

  void _prev() {
    if (_grading || _idx <= 0) return;
    _persistOpenFromField();
    setState(() {
      _idx -= 1;
      _applyQuestionToControllers();
    });
  }

  void _next() {
    if (_grading || !_canAdvance()) return;
    _persistOpenFromField();
    if (_idx >= widget.questions.length - 1) {
      _submitAll();
      return;
    }
    setState(() {
      _idx += 1;
      _applyQuestionToControllers();
    });
  }

  Future<void> _submitAll() async {
    _persistOpenFromField();
    for (final q in widget.questions) {
      if (q.type == TestQuestionType.open) {
        final t = (_openDraft[q.cardId] ?? '').trim();
        if (t.length < 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alla öppna svar måste vara minst tre tecken.')),
          );
          return;
        }
      } else {
        if (!_mcChoice.containsKey(q.cardId)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Markera ett svar för varje flervalsfråga.')),
          );
          return;
        }
      }
    }

    setState(() {
      _grading = true;
      _gradeStatus = '';
    });

    final outcomes = <TestOutcome>[];
    try {
      for (var i = 0; i < widget.questions.length; i++) {
        if (!mounted) return;
        setState(() {
          _gradeStatus = 'Bedömer… (${i + 1}/${widget.questions.length})';
        });
        final q = widget.questions[i];
        final card = widget.cardsById[q.cardId]!;
        if (q.type == TestQuestionType.multipleChoice &&
            q.correctIndex != null &&
            q.options != null) {
          final sel = _mcChoice[q.cardId];
          final ok = sel != null && sel == q.correctIndex;
          outcomes.add(TestOutcome(
            question: q,
            card: card,
            verdict: ok ? 'correct' : 'wrong',
            feedback: ok
                ? 'Rätt svar!'
                : 'Tyvärr inte rätt. Facit för kortet visas nedan.',
          ));
        } else {
          final answer = (_openDraft[q.cardId] ?? '').trim();
          final graded = await _ai.gradeAnswer(
            deckId: q.deckId,
            cardId: q.cardId,
            userAnswer: answer,
          );
          outcomes.add(TestOutcome(
            question: q,
            card: card,
            verdict: graded.verdict,
            feedback: graded.feedback,
          ));
        }
      }

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TestResultScreen(
            deckRepository: widget.deckRepository,
            outcomes: outcomes,
            subjectByDeckId: widget.subjectByDeckId,
            xpRepository: widget.xpRepository,
            uid: widget.uid,
          ),
        ),
      );
    } on AiAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on AiInvalidInputException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on AiUnavailableException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        showFriendlySnack(
          context,
          'Hoppsan – det gick inte att rätta provet. Testa igen om en stund.',
          error: e,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _grading = false;
          _gradeStatus = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isLast = _idx >= widget.questions.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _maybePopRoute();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _grading ? null : () => _maybePopRoute(),
          ),
          title: Text('${_idx + 1} av ${widget.questions.length}'),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: MiraiAdaptiveBox(
                  child: ListView(
                    padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                    children: [
                      Text(
                        _q.front,
                        style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      if ((_q.sourceQuote ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: MiraiTokens.spaceMd),
                        SourceCitationSection(
                          quote: _q.sourceQuote!.trim(),
                          dense: true,
                        ),
                      ],
                      const SizedBox(height: MiraiTokens.spaceLg),
                      if (_q.type == TestQuestionType.open)
                        TextField(
                          controller: _openAnswerCtrl,
                          minLines: 4,
                          maxLines: 6,
                          enabled: !_grading,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Skriv ditt svar',
                            border: OutlineInputBorder(),
                          ),
                        )
                      else ...[
                        for (var i = 0; i < (_q.options?.length ?? 0); i++) ...[
                          _McOptionTile(
                            label: _q.options![i],
                            selected: _mcChoice[_q.cardId] == i,
                            enabled: !_grading,
                            onTap: () =>
                                setState(() => _mcChoice[_q.cardId] = i),
                          ),
                          const SizedBox(height: MiraiTokens.spaceXs),
                        ],
                      ],
                      const SizedBox(height: MiraiTokens.spaceMd),
                      if (isLast)
                        Text(
                          'Tryck för att lämna in hela provet. När du har lämnat in '
                          'bedöms öppna svar först då.',
                          textAlign: TextAlign.center,
                          style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                        ),
                      const SizedBox(height: MiraiTokens.spaceSm),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  !_grading && _idx > 0 ? _prev : null,
                              child: const Text('Tillbaka'),
                            ),
                          ),
                          const SizedBox(width: MiraiTokens.spaceSm),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: !_grading && _canAdvance() ? _next : null,
                              child: Text(isLast ? 'Lämna in' : 'Nästa'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_grading)
                ModalBarrier(color: Colors.black.withValues(alpha: 0.35)),
              if (_grading)
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: MiraiTokens.bgRaised,
                      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                      border: Border.all(color: MiraiTokens.borderSubtle),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 22,
                          color: Color(0x22000000),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          const SizedBox(height: MiraiTokens.spaceMd),
                          Text(
                            _gradeStatus.isEmpty ? 'Bedömer…' : _gradeStatus,
                            style: tt.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _McOptionTile extends StatelessWidget {
  const _McOptionTile({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: MiraiTokens.bgRaised,
      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: MiraiTokens.spaceMd,
            vertical: MiraiTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            border: Border.all(
              color: selected ? MiraiTokens.accent : MiraiTokens.borderSubtle,
              width: selected ? MiraiTokens.borderThin * 2 : MiraiTokens.borderThin,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? MiraiTokens.accent : MiraiTokens.textTertiary,
                  size: 22,
                ),
              ),
              const SizedBox(width: MiraiTokens.spaceSm),
              Expanded(child: Text(label, style: tt.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}
