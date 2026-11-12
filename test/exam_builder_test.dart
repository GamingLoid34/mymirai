import 'package:flutter_test/flutter_test.dart';

import 'package:my_mirai/models/flashcard.dart';
import 'package:my_mirai/models/flashcard_deck.dart';
import 'package:my_mirai/services/exam_builder.dart';

void main() {
  final stamp = DateTime(2026, 1, 15);

  FlashcardDeck deck(String id) => FlashcardDeck(
        id: id,
        familyId: 'fam',
        homeworkId: 'hw',
        title: id,
        createdAt: stamp,
        updatedAt: stamp,
        cardCount: 0,
      );

  Flashcard card({
    required String id,
    required String deckId,
    DateTime? nextReviewAt,
    DateTime? lastReviewedAt,
  }) {
    return Flashcard(
      id: id,
      deckId: deckId,
      familyId: 'fam',
      front: id,
      back: 'b',
      source: FlashcardSource.manual,
      createdAt: stamp,
      updatedAt: stamp,
      lastReviewedAt: lastReviewedAt,
      nextReviewAt: nextReviewAt,
    );
  }

  test('empty pool yields no cards', () {
    expect(
      ExamBuilder.buildExamCards(
        decks: [deck('d1')],
        allCards: const [],
        count: 10,
        mode: ExamMode.study,
      ),
      isEmpty,
    );
  });

  test('only cards from selected decks are eligible', () {
    final decks = [deck('a'), deck('b')];
    final all = [
      card(id: 'c1', deckId: 'a'),
      card(id: 'c2', deckId: 'b'),
      card(id: 'cX', deckId: 'other'),
    ];
    final out = ExamBuilder.buildExamCards(
      decks: decks,
      allCards: all,
      count: 10,
      mode: ExamMode.quiz,
    );
    expect(out.map((e) => e.id).toSet(), {'c1', 'c2'});
  });

  test('clips to count when pool is larger', () {
    final d = deck('solo');
    final all = [
      for (var i = 0; i < 20; i++)
        card(
          id: 'k$i',
          deckId: 'solo',
          nextReviewAt: stamp.subtract(Duration(hours: i)),
        ),
    ];
    final out = ExamBuilder.buildExamCards(
      decks: [d],
      allCards: all,
      count: 5,
      mode: ExamMode.study,
    );
    expect(out.length, 5);
    expect(out.every((c) => c.deckId == 'solo'), isTrue);
  });
}
