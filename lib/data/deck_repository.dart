import '../models/flashcard.dart';
import '../models/flashcard_deck.dart';

abstract class DeckRepository {
  Stream<List<FlashcardDeck>> watchDecksForFamily();

  Stream<List<FlashcardDeck>> watchDecksForHomework(String homeworkId);

  Stream<FlashcardDeck?> watchDeck(String deckId);

  Stream<List<Flashcard>> watchCardsInDeck(String deckId);

  Future<FlashcardDeck> createDeck({
    required String homeworkId,
    required String title,
    String? subject,
  });

  Future<void> deleteDeck(String deckId);

  Future<Flashcard> createCard({
    required String deckId,
    required String front,
    required String back,
    required FlashcardSource source,
  });

  Future<void> updateCard(Flashcard card);

  Future<void> deleteCard(String cardId);

  /// Bulk-creation — atomic batch (t.ex. efter lokalt kopierande av AI-resultat).
  Future<void> createCardsBulk({
    required String deckId,
    required List<({String front, String back})> cards,
  });
}
