import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/flashcard.dart';
import '../models/flashcard_deck.dart';
import 'deck_repository.dart';

class FirestoreDeckRepository implements DeckRepository {
  FirestoreDeckRepository({
    required String familyId,
    FirebaseFirestore? firestore,
  })  : _familyId = familyId,
        _db = firestore ?? FirebaseFirestore.instance;

  final String _familyId;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _decks =>
      _db.collection('decks');

  CollectionReference<Map<String, dynamic>> get _flashcards =>
      _db.collection('flashcards');

  @override
  Stream<List<FlashcardDeck>> watchDecksForFamily() {
    return _decks
        .where('familyId', isEqualTo: _familyId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map(FlashcardDeck.fromFirestore).toList(growable: false));
  }

  @override
  Stream<List<FlashcardDeck>> watchDecksForHomework(String homeworkId) {
    return _decks
        .where('familyId', isEqualTo: _familyId)
        .where('homeworkId', isEqualTo: homeworkId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map(FlashcardDeck.fromFirestore).toList(growable: false));
  }

  @override
  Stream<FlashcardDeck?> watchDeck(String deckId) {
    return _decks.doc(deckId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      final d = FlashcardDeck.fromFirestore(snap);
      if (d.familyId != _familyId) return null;
      return d;
    });
  }

  @override
  Stream<List<Flashcard>> watchCardsInDeck(String deckId) {
    // familyId måste ingå i själva frågan (inte bara filtreras i klienten
    // efteråt) — annars kan Firestore-reglernas list-koll inte bevisas och
    // hela queryn nekas med PERMISSION_DENIED.
    return _flashcards
        .where('deckId', isEqualTo: deckId)
        .where('familyId', isEqualTo: _familyId)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map(Flashcard.fromFirestore).toList(growable: false));
  }

  @override
  Future<FlashcardDeck> createDeck({
    required String homeworkId,
    required String title,
    String? subject,
  }) async {
    final now = DateTime.now();
    final ref = _decks.doc();
    await ref.set({
      'familyId': _familyId,
      'homeworkId': homeworkId,
      'title': title,
      'subject': subject,
      'cardCount': 0,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    final snap = await ref.get();
    return FlashcardDeck.fromFirestore(snap);
  }

  /// Hämtar alla kort-id för ett deck (för radering i batchar).
  Future<List<String>> _cardIdsForDeck(String deckId) async {
    final q = await _flashcards.where('deckId', isEqualTo: deckId).get();
    return q.docs.map((d) => d.id).toList();
  }

  @override
  Future<void> deleteDeck(String deckId) async {
    final deckSnap = await _decks.doc(deckId).get();
    if (!deckSnap.exists) return;
    final d = FlashcardDeck.fromFirestore(deckSnap);
    if (d.familyId != _familyId) return;

    const chunk = 450;
    var ids = await _cardIdsForDeck(deckId);
    while (ids.isNotEmpty) {
      final batch = _db.batch();
      final slice = ids.length > chunk ? ids.take(chunk).toList() : ids;
      ids = ids.length > chunk ? ids.sublist(chunk) : [];
      for (final id in slice) {
        batch.delete(_flashcards.doc(id));
      }
      await batch.commit();
    }
    await _decks.doc(deckId).delete();
  }

  @override
  Future<Flashcard> createCard({
    required String deckId,
    required String front,
    required String back,
    required FlashcardSource source,
  }) async {
    final deckRef = _decks.doc(deckId);
    final deckSnap = await deckRef.get();
    if (!deckSnap.exists) {
      throw StateError('Deck saknas: $deckId');
    }
    final dd = FlashcardDeck.fromFirestore(deckSnap);
    if (dd.familyId != _familyId) {
      throw StateError('Otillåten åtkomst till deck.');
    }

    final now = DateTime.now();
    final cardRef = _flashcards.doc();
    await _db.runTransaction((tx) async {
      tx.set(cardRef, {
        'deckId': deckId,
        'familyId': _familyId,
        'front': front.trim(),
        'back': back.trim(),
        'source': source.firestoreValue,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'repetitions': 0,
        'easeFactor': 2.5,
        'intervalDays': 0,
        'lastReviewedAt': null,
        'nextReviewAt': null,
      });
      tx.update(deckRef, {
        'cardCount': FieldValue.increment(1),
        'updatedAt': Timestamp.fromDate(now),
      });
    });

    final got = await cardRef.get();
    return Flashcard.fromFirestore(got);
  }

  @override
  Future<void> updateCard(Flashcard card) async {
    if (card.familyId != _familyId) return;
    final now = DateTime.now();
    final ref = _flashcards.doc(card.id);
    await ref.update({
      ...card.copyWith(updatedAt: now).toMap(),
    });
    final deckRef = _decks.doc(card.deckId);
    await deckRef.update({
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  @override
  Future<void> deleteCard(String cardId) async {
    final ref = _flashcards.doc(cardId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final card = Flashcard.fromFirestore(snap);
    if (card.familyId != _familyId) return;

    final deckRef = _decks.doc(card.deckId);
    final now = DateTime.now();
    await _db.runTransaction((tx) async {
      tx.delete(ref);
      final deckSnap = await tx.get(deckRef);
      if (deckSnap.exists) {
        final data = deckSnap.data() ?? {};
        final fc = ((data['cardCount'] as num?) ?? 1).toInt();
        tx.update(deckRef, {
          'cardCount': fc > 0 ? fc - 1 : 0,
          'updatedAt': Timestamp.fromDate(now),
        });
      }
    });
  }

  @override
  Future<void> createCardsBulk({
    required String deckId,
    required List<({String front, String back})> cards,
  }) async {
    if (cards.isEmpty) return;
    final deckRef = _decks.doc(deckId);
    final deckSnap = await deckRef.get();
    if (!deckSnap.exists) {
      throw StateError('Deck saknas: $deckId');
    }
    final dd = FlashcardDeck.fromFirestore(deckSnap);
    if (dd.familyId != _familyId) {
      throw StateError('Otillåten åtkomst till deck.');
    }

    final now = DateTime.now();

    /// Firestore batch max 500; lämna marginal till deck‑uppdatering per batch.
    const batchMaxWrites = 450;
    var index = 0;
    final n = cards.length;
    while (index < n) {
      final batch = _db.batch();
      var added = 0;
      while (index < n && added < batchMaxWrites) {
        final c = cards[index++];
        added++;
        final cardRef = _flashcards.doc();
        batch.set(cardRef, {
          'deckId': deckId,
          'familyId': _familyId,
          'front': c.front.trim(),
          'back': c.back.trim(),
          'source': FlashcardSource.ai.firestoreValue,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
          'repetitions': 0,
          'easeFactor': 2.5,
          'intervalDays': 0,
          'lastReviewedAt': null,
          'nextReviewAt': null,
        });
      }
      batch.update(deckRef, {
        'cardCount': FieldValue.increment(added),
        'updatedAt': Timestamp.fromDate(now),
      });
      await batch.commit();
    }
  }
}
