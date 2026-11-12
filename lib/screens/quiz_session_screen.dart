import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../data/deck_repository.dart';
import '../data/dev_session_log_repository.dart';
import '../data/firestore_session_log_repository.dart';
import '../data/session_log_repository.dart';
import '../data/xp_repository.dart';
import '../models/flashcard.dart';
import '../models/flashcard_deck.dart';
import '../models/study_session_log.dart';
import '../services/ai_service.dart';
import '../services/xp_rules.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../widgets/celebration.dart';
import '../widgets/session_timer_bar.dart';
import '../widgets/source_citation_section.dart';
import '../widgets/xp_chip.dart';

class QuizSessionScreen extends StatefulWidget {
  const QuizSessionScreen({
    super.key,
    required this.deckRepository,
    this.deck,
    required this.cards,
    this.subjectByDeckId,
    this.examDeckCount,
    this.xpRepository,
    this.uid,
    this.sessionDurationMinutes,
    this.homeworkId,
    this.sessionLogRepository,
  });

  final DeckRepository deckRepository;
  final FlashcardDeck? deck;
  final List<Flashcard> cards;
  final Map<String, String>? subjectByDeckId;
  final int? examDeckCount;
  final XpRepository? xpRepository;
  final String? uid;
  final String? homeworkId;
  final SessionLogRepository? sessionLogRepository;

  /// `null` = ingen timer ("Tills korten är slut").
  final int? sessionDurationMinutes;

  @override
  State<QuizSessionScreen> createState() => _QuizSessionScreenState();
}

class _QuizSessionScreenState extends State<QuizSessionScreen> {
  final _ai = AiService();
  final _answerCtrl = TextEditingController();
  final _startedAt = DateTime.now();
  int _currentIndex = 0;
  bool _grading = false;
  GradeResult? _result;
  final Map<String, String> _results = {};

  bool _celebrated = false;
  bool _timeUpPending = false;
  bool _keepGoing = false;

  bool get _isDone => _results.length >= widget.cards.length;
  Flashcard get _card => widget.cards[_currentIndex];

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  void _awardXp(int amount) {
    final xp = widget.xpRepository;
    final uid = widget.uid;
    if (xp == null || uid == null) return;
    xp.addXp(uid, amount);
    if (mounted) XpChip.show(context, amount);
  }

  void _onTimeUp() {
    if (_isDone || _keepGoing) return;
    if (_grading || _result != null) {
      // Vänta tills pågående fråga är klar (bedömd + Nästa tryckt).
      _timeUpPending = true;
      return;
    }
    _showPauseDialog();
  }

  Future<void> _showPauseDialog() async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Bra kämpat! 🙌'),
        content: const Text('Vill du ta paus eller köra lite till?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('more'),
            child: const Text('Kör lite till'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('pause'),
            child: const Text('Ta paus'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'pause') {
      Navigator.of(context).pop(_results.isNotEmpty);
    } else {
      setState(() => _keepGoing = true);
    }
  }

  Future<void> _submit() async {
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty || _grading) return;
    setState(() => _grading = true);
    try {
      final graded = await _ai.gradeAnswer(
        deckId: _card.deckId,
        cardId: _card.id,
        userAnswer: answer,
      );
      await widget.deckRepository.updateCard(
        _card.copyWith(
          lastQuizVerdict: graded.verdict,
          lastQuizAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = graded;
        _results[_card.id] = graded.verdict;
        _grading = false;
      });
      if (graded.verdict == 'correct' && !kIsWeb) {
        HapticFeedback.lightImpact();
      }
      if (_isDone && !_celebrated && mounted) {
        _celebrated = true;
        Celebration.show(context, size: CelebrationSize.medium);
        _awardXp(XpRules.quizDone);
        _logSession();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _grading = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att bedöma svaret. Testa igen om en stund.',
        error: e,
      );
    }
  }

  void _logSession() {
    final hwId = widget.homeworkId ?? widget.deck?.homeworkId;
    if (hwId == null || hwId.isEmpty) return;
    final repo = widget.sessionLogRepository ??
        (kUseFirestoreHomework
            ? FirestoreSessionLogRepository()
            : DevSessionLogRepository());

    final missed = <String>[];
    var correctCount = 0;
    for (final c in widget.cards) {
      final verdict = _results[c.id] ?? '';
      if (verdict == 'correct') {
        correctCount++;
      } else {
        if (missed.length < 10) missed.add(c.front);
      }
    }

    final log = StudySessionLog(
      id: '',
      homeworkId: hwId,
      deckId: widget.deck?.id,
      userId: widget.uid ?? '',
      completedAt: DateTime.now(),
      totalCards: widget.cards.length,
      correctCards: correctCount,
      incorrectCards: widget.cards.length - correctCount,
      missedFronts: missed,
      durationSeconds: DateTime.now().difference(_startedAt).inSeconds,
      mode: 'written',
    );
    repo.saveLog(log);
  }

  void _next() {
    if (_currentIndex >= widget.cards.length - 1) {
      setState(() {});
      return;
    }
    setState(() {
      _currentIndex += 1;
      _result = null;
      _answerCtrl.clear();
    });
    if (_timeUpPending) {
      _timeUpPending = false;
      _showPauseDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(_isDone ? 'Klar' : '${_currentIndex + 1} av ${widget.cards.length}'),
        bottom: (widget.sessionDurationMinutes != null && !_isDone && !_keepGoing)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: SessionTimerBar(
                  key: ValueKey(widget.sessionDurationMinutes),
                  duration: Duration(minutes: widget.sessionDurationMinutes!),
                  onTimeUp: _onTimeUp,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: MiraiAdaptiveBox(
            child: _isDone ? _buildSummary(tt) : _buildQuiz(tt),
          ),
        ),
      ),
    );
  }

  Widget _buildQuiz(TextTheme tt) {
    final hasResult = _result != null;
    final canSubmit =
        _answerCtrl.text.trim().isNotEmpty && !_grading && !hasResult;
    return Padding(
      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: MiraiTokens.spaceMd),
          Text(
            _card.front,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          if ((_card.sourceQuote ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: MiraiTokens.spaceMd),
            SourceCitationSection(
              quote: _card.sourceQuote!.trim(),
              dense: true,
            ),
          ],
          const SizedBox(height: MiraiTokens.spaceLg),
          TextField(
            controller: _answerCtrl,
            minLines: 4,
            maxLines: 6,
            enabled: !_grading && !hasResult,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Skriv ditt svar',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
          FilledButton(
            onPressed: canSubmit ? _submit : null,
            child: _grading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Skicka svar'),
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
          if (_result != null) _ResultPanel(result: _result!, card: _card, onNext: _next),
        ],
      ),
    );
  }

  Widget _buildSummary(TextTheme tt) {
    int count(String verdict) => _results.values.where((v) => v == verdict).length;
    final elapsed = DateTime.now().difference(_startedAt);
    final mm = elapsed.inMinutes;
    final ss = elapsed.inSeconds % 60;
    return Padding(
      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.quiz_rounded,
            size: 56,
            color: MiraiTokens.accent,
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
          Text('Förhör klart!', style: tt.headlineMedium),
          const SizedBox(height: MiraiTokens.spaceMd),
          if (widget.deck == null && widget.examDeckCount != null)
            Text(
              'Du förhördes på ${widget.cards.length} kort från ${widget.examDeckCount} decks',
              style: tt.bodyLarge,
              textAlign: TextAlign.center,
            )
          else
            const SizedBox.shrink(),
          if (widget.deck == null && widget.subjectByDeckId != null) ...[
            const SizedBox(height: MiraiTokens.spaceSm),
            ..._subjectStats(tt),
          ],
          Text('Rätt: ${count('correct')}', style: tt.bodyLarge),
          Text('Delvis: ${count('partial')}', style: tt.bodyLarge),
          Text('Fel: ${count('wrong')}', style: tt.bodyLarge),
          const SizedBox(height: MiraiTokens.spaceSm),
          Text(
            'Tid: ${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}',
            style: tt.bodyMedium?.copyWith(color: MiraiTokens.textSecondary),
          ),
          const SizedBox(height: MiraiTokens.spaceLg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Klar'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _subjectStats(TextTheme tt) {
    final map = <String, int>{};
    for (final c in widget.cards) {
      final subject = widget.subjectByDeckId?[c.deckId] ?? 'Okänt ämne';
      map[subject] = (map[subject] ?? 0) + 1;
    }
    return map.entries
        .map(
          (e) => Text(
            '${e.key}: ${e.value} kort',
            style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
          ),
        )
        .toList();
  }
}

class _ResultPanel extends StatefulWidget {
  const _ResultPanel({
    required this.result,
    required this.card,
    required this.onNext,
  });

  final GradeResult result;
  final Flashcard card;
  final VoidCallback onNext;

  @override
  State<_ResultPanel> createState() => _ResultPanelState();
}

class _ResultPanelState extends State<_ResultPanel>
    with SingleTickerProviderStateMixin {
  bool _showAnswer = false;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulse = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOutBack),
    );
    if (widget.result.verdict == 'correct') _pulseCtrl.forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isCorrect = widget.result.verdict == 'correct';
    final isPartial = widget.result.verdict == 'partial';
    final bg = isCorrect
        ? MiraiTokens.success.withValues(alpha: 0.18)
        : isPartial
            ? MiraiTokens.warning.withValues(alpha: 0.18)
            : MiraiTokens.danger.withValues(alpha: 0.18);
    final icon = isCorrect ? '✓ Rätt' : (isPartial ? '◐ Delvis' : '✗ Fel');

    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MiraiTokens.spaceMd),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: MiraiTokens.spaceXs),
          Text(widget.result.feedback, style: tt.bodyMedium),
          if (!isCorrect && (!isPartial || _showAnswer)) ...[
            const SizedBox(height: MiraiTokens.spaceSm),
            Text(
              'Facit: ${widget.card.back}',
              style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
            ),
          ],
          const SizedBox(height: MiraiTokens.spaceSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isPartial && !_showAnswer) ...[
                TextButton(
                  onPressed: () => setState(() => _showAnswer = true),
                  child: const Text('Visa facit'),
                ),
                const SizedBox(width: MiraiTokens.spaceSm),
              ],
              FilledButton(
                onPressed: widget.onNext,
                child: const Text('Nästa'),
              ),
            ],
          ),
        ],
      ),
    );

    if (!isCorrect) return content;
    return ScaleTransition(scale: _pulse, child: content);
  }
}
