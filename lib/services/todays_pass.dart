import 'dart:math';

import '../models/flashcard.dart';
import '../models/flashcard_deck.dart';
import 'spaced_repetition.dart';

/// Bygger "Dagens pass": alla due-kort ur familjens lekar, blandade.
///
/// [seed] gör blandningen deterministisk (för test); utelämna för riktig
/// slump i produktion.
List<Flashcard> buildTodaysPass({
  required List<FlashcardDeck> decks,
  required List<Flashcard> allCards,
  required DateTime now,
  int? seed,
}) {
  final deckIds = decks.map((d) => d.id).toSet();
  final pool = allCards.where((c) => deckIds.contains(c.deckId)).toList();
  final due = SpacedRepetition.filterDue(pool, now);
  final shuffled = [...due];
  shuffled.shuffle(seed == null ? Random() : Random(seed));
  return shuffled;
}
