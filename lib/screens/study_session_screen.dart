import 'dart:math' as math;

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
import '../services/spaced_repetition.dart';
import '../services/xp_rules.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../util/session_summary.dart';
import '../widgets/celebration.dart';
import '../widgets/session_timer_bar.dart';
import '../widgets/source_citation_section.dart';
import '../widgets/xp_chip.dart';

class StudySessionScreen extends StatefulWidget {
  const StudySessionScreen({
    super.key,
    required this.deckRepository,
    this.deck,
    required this.cards,
    this.subjectByDeckId,
    this.examDeckCount,
    this.xpRepository,
    this.uid,
    this.sessionDurationMinutes,
    this.simplifiedRating = false,
    this.sessionTitle,
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

  /// Om sant: förhörsläge med två knappar (Kunde inte / Kunde) som matar SM-2.
  final bool simplifiedRating;

  /// Valfri titel i AppBaren (default: räknaren "$i av $n").
  final String? sessionTitle;

  @override
  State<StudySessionScreen> createState() => _StudySessionScreenState();
}

class _StudySessionScreenState extends State<StudySessionScreen> {
  final _startedAt = DateTime.now();
  int _currentIndex = 0;
  bool _showingBack = false;
  bool _saving = false;
  bool _showDetails = false;
  bool _celebrated = false;
  bool _timeUpPending = false;
  bool _keepGoing = false;
  final Map<String, ReviewQuality> _sessionResults = {};

  bool get _isDone => _sessionResults.length >= widget.cards.length;

  Flashcard get _currentCard => widget.cards[_currentIndex];

  void _onTimeUp() {
    if (_isDone || _keepGoing) return;
    if (_saving) {
      // Vänta tills pågående kort är besvarat innan pausdialogen visas.
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
      Navigator.of(context).pop(_sessionResults.isNotEmpty);
    } else {
      setState(() => _keepGoing = true);
    }
  }

  Future<void> _tryExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avsluta sessionen?'),
        content: const Text('Din pågående repetition avbryts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Avsluta'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  void _awardXp(int amount) {
    final xp = widget.xpRepository;
    final uid = widget.uid;
    if (xp == null || uid == null) return;
    xp.addXp(uid, amount);
    if (mounted) XpChip.show(context, amount);
  }

  Future<void> _rate(ReviewQuality quality) async {
    if (_saving) return;
    if (!kIsWeb) await HapticFeedback.selectionClick();
    final now = DateTime.now();
    final card = _currentCard;
    final updated = SpacedRepetition.apply(card, quality, now);
    setState(() => _saving = true);
    try {
      await widget.deckRepository.updateCard(updated);
      if (!mounted) return;
      setState(() {
        _sessionResults[card.id] = quality;
        if (_currentIndex < widget.cards.length - 1) {
          _currentIndex += 1;
          _showingBack = false;
        }
        _saving = false;
      });
      _awardXp(XpRules.flashcardReviewed);
      if (_isDone && !_celebrated && mounted) {
        _celebrated = true;
        if (widget.simplifiedRating) {
          _awardXp(XpRules.quizDone);
        }
        Celebration.show(context, size: CelebrationSize.medium);
        _logSession();
      } else if (_timeUpPending && mounted) {
        _timeUpPending = false;
        _showPauseDialog();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara repetitionen. Testa igen om en stund.',
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

    final summary = buildSessionSummary(
      cards: widget.cards,
      results: _sessionResults,
    );

    final log = StudySessionLog(
      id: '',
      homeworkId: hwId,
      deckId: widget.deck?.id,
      userId: widget.uid ?? '',
      completedAt: DateTime.now(),
      totalCards: summary.total,
      correctCards: summary.satDirekt,
      incorrectCards: summary.total - summary.satDirekt,
      missedFronts: summary.comebackFronts,
      durationSeconds: DateTime.now().difference(_startedAt).inSeconds,
      mode: widget.simplifiedRating ? 'simplified' : 'standard',
    );
    repo.saveLog(log);
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
          onPressed: _tryExit,
          tooltip: 'Avsluta',
        ),
        title: Text(
          widget.sessionTitle ??
              (_isDone
                  ? 'Klar'
                  : '${_currentIndex + 1} av ${widget.cards.length}'),
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
        actions: const [
          SizedBox(width: 48),
        ],
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
            child: _isDone ? _buildSummary(tt) : _buildStudy(tt),
          ),
        ),
      ),
    );
  }

  Widget _buildStudy(TextTheme tt) {
    final card = _currentCard;
    final frontWidget = _faceContainer(
      key: const ValueKey('front'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subjectChip(tt),
          const Spacer(),
          Center(
            child: Text(
              card.front,
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          const Spacer(),
          Center(
            child: Text(
              'Tryck för att se svaret',
              style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
            ),
          ),
        ],
      ),
    );
    final backWidget = _faceContainer(
      key: const ValueKey('back'),
      accentLeft: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subjectChip(tt),
          const SizedBox(height: MiraiTokens.spaceSm),
          Text(
            card.front,
            style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
          Text(
            'SVAR',
            style: tt.labelSmall?.copyWith(
              letterSpacing: 0.5,
              color: MiraiTokens.textTertiary,
            ),
          ),
          const SizedBox(height: MiraiTokens.spaceXs),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    card.back,
                    style: tt.bodyLarge?.copyWith(height: 1.6),
                  ),
                  if ((card.sourceQuote ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: MiraiTokens.spaceMd),
                    SourceCitationSection(
                      quote: card.sourceQuote!.trim(),
                      dense: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _saving ? null : () => setState(() => _showingBack = !_showingBack),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) {
                  final rotate = Tween(begin: math.pi, end: 0.0).animate(anim);
                  return AnimatedBuilder(
                    animation: rotate,
                    child: child,
                    builder: (context, c) {
                      final isUnder = (ValueKey(_showingBack) != c!.key);
                      final tilt =
                          isUnder ? math.min(rotate.value, math.pi / 2) : rotate.value;
                      return Transform(
                        transform: Matrix4.rotationY(tilt),
                        alignment: Alignment.center,
                        child: c,
                      );
                    },
                  );
                },
                layoutBuilder: (currentChild, _) => currentChild!,
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                child: _showingBack ? backWidget : frontWidget,
              ),
            ),
          ),
          const SizedBox(height: MiraiTokens.spaceLg),
          if (!_showingBack)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : () => setState(() => _showingBack = true),
                child: const Text('Visa svar'),
              ),
            )
          else if (widget.simplifiedRating)
            _SimplifiedReviewButtons(
              disabled: _saving,
              onKundeInte: () => _rate(ReviewQuality.again),
              onKunde: () => _rate(ReviewQuality.good),
            )
          else
            _ReviewButtons(
              card: card,
              disabled: _saving,
              onPressed: _rate,
            ),
        ],
      ),
    );
  }

  Widget _buildSummary(TextTheme tt) {
    int count(ReviewQuality q) =>
        _sessionResults.values.where((v) => v == q).length;
    final summary = buildSessionSummary(
      cards: widget.cards,
      results: _sessionResults,
    );
    final headerTitle =
        widget.simplifiedRating ? 'Förhör klart! 🎉' : 'Snyggt jobbat! 🌟';
    return Padding(
      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.celebration_rounded,
            size: 56,
            color: MiraiTokens.success,
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
          Text(headerTitle, style: tt.headlineMedium),
          const SizedBox(height: MiraiTokens.spaceSm),
          Text(
            'Du klarade ${summary.total} kort – ${summary.satDirekt} satt direkt.',
            style: tt.bodyLarge,
            textAlign: TextAlign.center,
          ),
          if (summary.comebackFronts.isNotEmpty) ...[
            const SizedBox(height: MiraiTokens.spaceSm),
            Text(
              'Kommer igen imorgon: ${summary.comebackFronts.join(', ')}${summary.truncated ? ' …' : ''}',
              style: tt.bodyMedium?.copyWith(
                color: MiraiTokens.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: MiraiTokens.spaceMd),
          if (!_showDetails)
            TextButton(
              onPressed: () => setState(() => _showDetails = true),
              child: const Text('Visa detaljer'),
            )
          else ...[
            if (widget.deck == null && widget.examDeckCount != null)
              Text(
                'Du studerade ${widget.cards.length} kort från ${widget.examDeckCount} decks',
                style: tt.bodyMedium,
                textAlign: TextAlign.center,
              ),
            if (widget.deck == null && widget.subjectByDeckId != null) ...[
              const SizedBox(height: MiraiTokens.spaceSm),
              ..._subjectStats(tt),
            ],
            const SizedBox(height: MiraiTokens.spaceXs),
            if (widget.simplifiedRating) ...[
              Text(
                'Kunde: ${count(ReviewQuality.good)} · Kunde inte: ${count(ReviewQuality.again)}',
                style: tt.bodyMedium,
              ),
            ] else ...[
              Text('Igen: ${count(ReviewQuality.again)}', style: tt.bodyMedium),
              Text('Svårt: ${count(ReviewQuality.hard)}', style: tt.bodyMedium),
              Text('Bra: ${count(ReviewQuality.good)}', style: tt.bodyMedium),
              Text('Lätt: ${count(ReviewQuality.easy)}', style: tt.bodyMedium),
              if (summary.comebackFronts.isEmpty) ...[
                const SizedBox(height: MiraiTokens.spaceMd),
                Text(
                  'Du ska repetera några kort om 1 dag, andra om 6 dagar.',
                  style: tt.bodyMedium?.copyWith(color: MiraiTokens.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
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

  Widget _faceContainer({
    required Widget child,
    required Key key,
    bool accentLeft = false,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 280),
      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
      decoration: BoxDecoration(
        color: MiraiTokens.bgRaised,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusLg),
        border: Border.all(
          color: MiraiTokens.borderSubtle,
          width: MiraiTokens.borderThin,
        ),
      ),
      child: Row(
        children: [
          if (accentLeft)
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: MiraiTokens.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          if (accentLeft) const SizedBox(width: MiraiTokens.spaceMd),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _subjectChip(TextTheme tt) {
    final subjectRaw = (widget.deck?.subject ?? '').trim();
    final subject = subjectRaw.isEmpty ? 'Flashcards' : subjectRaw;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: MiraiTokens.accentSoft,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
      ),
      child: Text(
        subject,
        style: tt.labelSmall?.copyWith(color: MiraiTokens.textSecondary),
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

class _ReviewButtons extends StatelessWidget {
  const _ReviewButtons({
    required this.card,
    required this.disabled,
    required this.onPressed,
  });

  final Flashcard card;
  final bool disabled;
  final void Function(ReviewQuality q) onPressed;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final rows = [
      (q: ReviewQuality.again, label: 'Igen', color: MiraiTokens.danger),
      (q: ReviewQuality.hard, label: 'Svårt', color: MiraiTokens.warning),
      (q: ReviewQuality.good, label: 'Bra', color: MiraiTokens.success),
      (q: ReviewQuality.easy, label: 'Lätt', color: MiraiTokens.info),
    ];
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                OutlinedButton(
                  onPressed: disabled ? null : () => onPressed(rows[i].q),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: rows[i].color, width: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    foregroundColor: rows[i].color,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: Text(rows[i].label),
                ),
                const SizedBox(height: 2),
                Text(
                  _daysLabel(SpacedRepetition.apply(card, rows[i].q, now).intervalDays),
                  style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                ),
              ],
            ),
          ),
          if (i < rows.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

String _daysLabel(int days) => days == 1 ? '1 dag' : '$days dagar';

class _SimplifiedReviewButtons extends StatelessWidget {
  const _SimplifiedReviewButtons({
    required this.disabled,
    required this.onKundeInte,
    required this.onKunde,
  });

  final bool disabled;
  final VoidCallback onKundeInte;
  final VoidCallback onKunde;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: disabled ? null : onKundeInte,
            style: FilledButton.styleFrom(
              backgroundColor: MiraiTokens.danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: MiraiTokens.spaceMd),
              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            child: const Text('Kunde inte'),
          ),
        ),
        const SizedBox(width: MiraiTokens.spaceMd),
        Expanded(
          child: FilledButton(
            onPressed: disabled ? null : onKunde,
            style: FilledButton.styleFrom(
              backgroundColor: MiraiTokens.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: MiraiTokens.spaceMd),
              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            child: const Text('Kunde'),
          ),
        ),
      ],
    );
  }
}
