import 'dart:math';

import '../models/flashcard.dart';
import '../models/flashcard_deck.dart';
import 'spaced_repetition.dart';

enum ExamMode {
  study,
  quiz,
}

class ExamBuilder {
  ExamBuilder._();

  static List<Flashcard> buildExamCards({
    required List<FlashcardDeck> decks,
    required List<Flashcard> allCards,
    required int count,
    required ExamMode mode,
  }) {
    final selectedDeckIds = decks.map((d) => d.id).toSet();
    final pool = allCards
        .where((c) => selectedDeckIds.contains(c.deckId))
        .toList();
    final now = DateTime.now();
    final due = SpacedRepetition.sortForStudy(pool, now);
    final dueIds = due.map((c) => c.id).toSet();
    final neverReviewed = pool
        .where((c) => !dueIds.contains(c.id) && c.lastReviewedAt == null)
        .toList();
    final reviewed = pool
        .where((c) => !dueIds.contains(c.id) && c.lastReviewedAt != null)
        .toList()
      ..sort((a, b) => a.lastReviewedAt!.compareTo(b.lastReviewedAt!));

    final prioritized = <Flashcard>[
      ...due,
      ...neverReviewed,
      ...reviewed,
    ];
    final clipped = prioritized.take(count).toList();
    clipped.shuffle(Random());
    return clipped;
  }
}
