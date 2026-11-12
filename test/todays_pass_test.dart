import 'package:flutter_test/flutter_test.dart';

import 'package:my_mirai/models/flashcard.dart';
import 'package:my_mirai/models/flashcard_deck.dart';
import 'package:my_mirai/services/todays_pass.dart';

void main() {
  final stamp = DateTime(2026, 1, 15);
  final now = DateTime(2026, 5, 6);

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
      nextReviewAt: nextReviewAt,
    );
  }

  test('empty pool yields no cards', () {
    expect(
      buildTodaysPass(decks: [deck('d1')], allCards: const [], now: now),
      isEmpty,
    );
  });

  test('only due cards from the given decks are included', () {
    final decks = [deck('a'), deck('b')];
    final all = [
      card(id: 'due-a', deckId: 'a', nextReviewAt: now.subtract(const Duration(days: 1))),
      card(id: 'notdue-a', deckId: 'a', nextReviewAt: now.add(const Duration(days: 1))),
      card(id: 'due-b', deckId: 'b', nextReviewAt: null),
      card(id: 'due-other-deck', deckId: 'other', nextReviewAt: null),
    ];
    final out = buildTodaysPass(decks: decks, allCards: all, now: now, seed: 1);
    expect(out.map((e) => e.id).toSet(), {'due-a', 'due-b'});
  });

  test('same seed gives deterministic order', () {
    final decks = [deck('solo')];
    final all = [
      for (var i = 0; i < 10; i++) card(id: 'k$i', deckId: 'solo', nextReviewAt: null),
    ];
    final out1 = buildTodaysPass(decks: decks, allCards: all, now: now, seed: 42);
    final out2 = buildTodaysPass(decks: decks, allCards: all, now: now, seed: 42);
    expect(out1.map((c) => c.id).toList(), out2.map((c) => c.id).toList());
  });

  test('different seeds can give different order', () {
    final decks = [deck('solo')];
    final all = [
      for (var i = 0; i < 20; i++) card(id: 'k$i', deckId: 'solo', nextReviewAt: null),
    ];
    final out1 = buildTodaysPass(decks: decks, allCards: all, now: now, seed: 1);
    final out2 = buildTodaysPass(decks: decks, allCards: all, now: now, seed: 2);
    expect(out1.map((c) => c.id).toList(), isNot(out2.map((c) => c.id).toList()));
  });
}
