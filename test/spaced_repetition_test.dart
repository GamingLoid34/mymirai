import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/models/flashcard.dart';
import 'package:my_mirai/services/spaced_repetition.dart';

Flashcard _card({
  int repetitions = 0,
  double ease = 2.5,
  int intervalDays = 0,
  DateTime? nextReviewAt,
}) {
  final now = DateTime(2026, 1, 1, 12);
  return Flashcard(
    id: 'c1',
    deckId: 'd1',
    familyId: 'f1',
    front: 'Q',
    back: 'A',
    source: FlashcardSource.ai,
    createdAt: now,
    updatedAt: now,
    repetitions: repetitions,
    easeFactor: ease,
    intervalDays: intervalDays,
    lastReviewedAt: null,
    nextReviewAt: nextReviewAt,
  );
}

void main() {
  group('SpacedRepetition.apply', () {
    test('new card + good => reps 1, interval 1, next +1 day', () {
      final now = DateTime(2026, 1, 10, 9);
      final updated = SpacedRepetition.apply(_card(), ReviewQuality.good, now);
      expect(updated.repetitions, 1);
      expect(updated.intervalDays, 1);
      expect(updated.nextReviewAt, now.add(const Duration(days: 1)));
    });

    test('second good => reps 2, interval 6', () {
      final now = DateTime(2026, 1, 10, 9);
      final updated = SpacedRepetition.apply(
        _card(repetitions: 1, intervalDays: 1),
        ReviewQuality.good,
        now,
      );
      expect(updated.repetitions, 2);
      expect(updated.intervalDays, 6);
    });

    test('third good => interval previous * ease', () {
      final now = DateTime(2026, 1, 10, 9);
      final updated = SpacedRepetition.apply(
        _card(repetitions: 2, intervalDays: 6, ease: 2.5),
        ReviewQuality.good,
        now,
      );
      expect(updated.intervalDays, 15);
    });

    test('again on mature card resets reps and interval and lowers ease', () {
      final now = DateTime(2026, 1, 10, 9);
      final updated = SpacedRepetition.apply(
        _card(repetitions: 8, intervalDays: 30, ease: 2.2),
        ReviewQuality.again,
        now,
      );
      expect(updated.repetitions, 0);
      expect(updated.intervalDays, 1);
      expect(updated.easeFactor, lessThan(2.2));
    });

    test('easy gives longer interval than good', () {
      final now = DateTime(2026, 1, 10, 9);
      final base = _card(repetitions: 3, intervalDays: 8, ease: 2.4);
      final good = SpacedRepetition.apply(base, ReviewQuality.good, now);
      final easy = SpacedRepetition.apply(base, ReviewQuality.easy, now);
      expect(easy.intervalDays, greaterThan(good.intervalDays));
    });

    test('ease is clamped to min 1.30 and max 2.50', () {
      final now = DateTime(2026, 1, 10, 9);
      final min = SpacedRepetition.apply(
        _card(ease: 1.3),
        ReviewQuality.again,
        now,
      );
      final max = SpacedRepetition.apply(
        _card(ease: 2.5),
        ReviewQuality.easy,
        now,
      );
      expect(min.easeFactor, 1.3);
      expect(max.easeFactor, 2.5);
    });
  });

  test('filterDue handles null/future/past dates', () {
    final now = DateTime(2026, 1, 10, 9);
    final cards = [
      _card(nextReviewAt: null),
      _card(nextReviewAt: now.add(const Duration(days: 1))),
      _card(nextReviewAt: now.subtract(const Duration(days: 1))),
    ];
    final due = SpacedRepetition.filterDue(cards, now);
    expect(due.length, 2);
  });
}
