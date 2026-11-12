import '../models/flashcard.dart';

enum ReviewQuality {
  again,
  hard,
  good,
  easy,
}

class SpacedRepetition {
  SpacedRepetition._();

  static Flashcard apply(Flashcard card, ReviewQuality quality, DateTime now) {
    int newReps;
    int newInterval;
    double newEase;

    if (quality == ReviewQuality.again) {
      newReps = 0;
      newInterval = 1;
      newEase = (card.easeFactor - 0.20).clamp(1.30, 2.50);
    } else {
      newReps = card.repetitions + 1;
      if (newReps == 1) {
        newInterval = 1;
      } else if (newReps == 2) {
        newInterval = 6;
      } else {
        newInterval = (card.intervalDays * card.easeFactor).round();
      }
      final q = quality.index.toDouble();
      newEase = (card.easeFactor + (0.10 - (3 - q) * (0.08 + (3 - q) * 0.02)))
          .clamp(1.30, 2.50);
      if (quality == ReviewQuality.easy) {
        newInterval = (newInterval * 1.3).round();
      }
    }

    return card.copyWith(
      repetitions: newReps,
      easeFactor: newEase,
      intervalDays: newInterval,
      lastReviewedAt: now,
      nextReviewAt: now.add(Duration(days: newInterval)),
      updatedAt: now,
    );
  }

  static List<Flashcard> filterDue(List<Flashcard> cards, DateTime now) {
    return cards.where((c) {
      if (c.nextReviewAt == null) return true;
      return !c.nextReviewAt!.isAfter(now);
    }).toList();
  }

  static List<Flashcard> sortForStudy(List<Flashcard> cards, DateTime now) {
    final due = filterDue(cards, now);
    due.sort((a, b) {
      if (a.nextReviewAt == null && b.nextReviewAt == null) return 0;
      if (a.nextReviewAt == null) return -1;
      if (b.nextReviewAt == null) return 1;
      return a.nextReviewAt!.compareTo(b.nextReviewAt!);
    });
    return due;
  }
}
