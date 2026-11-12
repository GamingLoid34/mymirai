import 'package:cloud_firestore/cloud_firestore.dart';

enum FlashcardSource {
  ai,
  manual,
  edited,
  vocabulary,
  /// Fråga/svar hämtade ordagrant från läxmaterialet (roadmap v5).
  extracted;

  String get firestoreValue => name;

  static FlashcardSource fromFirestore(String? v) {
    switch (v) {
      case 'manual':
        return FlashcardSource.manual;
      case 'edited':
        return FlashcardSource.edited;
      case 'vocabulary':
        return FlashcardSource.vocabulary;
      case 'extracted':
        return FlashcardSource.extracted;
      case 'ai':
      default:
        return FlashcardSource.ai;
    }
  }
}

class Flashcard {
  const Flashcard({
    required this.id,
    required this.deckId,
    required this.familyId,
    required this.front,
    required this.back,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.sourceQuote,
    this.repetitions = 0,
    this.easeFactor = 2.5,
    this.intervalDays = 0,
    this.lastReviewedAt,
    this.nextReviewAt,
    this.lastQuizVerdict,
    this.lastQuizAt,
  });

  final String id;
  final String deckId;
  final String familyId;
  final String front;
  final String back;
  /// Ordagrann kort citat hämtning ur läxmaterialet (Chunk X).
  final String? sourceQuote;
  final FlashcardSource source;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Antal lyckade reviews i rad (SM‑2, chunk 2).
  final int repetitions;
  /// SM‑2 ease, default 2.5.
  final double easeFactor;
  /// Dagar till nästa review (chunk 2).
  final int intervalDays;
  final DateTime? lastReviewedAt;
  final DateTime? nextReviewAt;
  final String? lastQuizVerdict;
  final DateTime? lastQuizAt;

  static Flashcard fromMap(String id, Map<String, dynamic> data) {
    final lr = data['lastReviewedAt'];
    final nr = data['nextReviewAt'];
    final lq = data['lastQuizAt'];
    final created = data['createdAt'];
    final updated = data['updatedAt'];
    return Flashcard(
      id: id,
      deckId: data['deckId'] as String? ?? '',
      familyId: data['familyId'] as String? ?? '',
      front: data['front'] as String? ?? '',
      back: data['back'] as String? ?? '',
      source:
          FlashcardSource.fromFirestore(data['source'] as String? ?? 'ai'),
      createdAt:
          created is Timestamp ? created.toDate() : DateTime.now(),
      updatedAt:
          updated is Timestamp ? updated.toDate() : DateTime.now(),
      repetitions: (data['repetitions'] as num?)?.toInt() ?? 0,
      easeFactor: (data['easeFactor'] as num?)?.toDouble() ?? 2.5,
      intervalDays: (data['intervalDays'] as num?)?.toInt() ?? 0,
      lastReviewedAt:
          lr is Timestamp ? lr.toDate() : null,
      nextReviewAt: nr is Timestamp ? nr.toDate() : null,
      lastQuizVerdict: data['lastQuizVerdict'] as String?,
      lastQuizAt: lq is Timestamp ? lq.toDate() : null,
    );
  }

  static Flashcard fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return Flashcard.fromMap(doc.id, data);
  }

  Map<String, dynamic> toMap() => {
        'deckId': deckId,
        'familyId': familyId,
        'front': front,
        'back': back,
        if (sourceQuote != null && sourceQuote!.trim().isNotEmpty)
          'sourceQuote': sourceQuote!.trim(),
        'source': source.firestoreValue,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'repetitions': repetitions,
        'easeFactor': easeFactor,
        'intervalDays': intervalDays,
        'lastReviewedAt':
            lastReviewedAt != null ? Timestamp.fromDate(lastReviewedAt!) : null,
        'nextReviewAt':
            nextReviewAt != null ? Timestamp.fromDate(nextReviewAt!) : null,
        'lastQuizVerdict': lastQuizVerdict,
        'lastQuizAt': lastQuizAt != null ? Timestamp.fromDate(lastQuizAt!) : null,
      };

  Flashcard copyWith({
    String? front,
    String? back,
    String? sourceQuote,
    FlashcardSource? source,
    DateTime? updatedAt,
    int? repetitions,
    double? easeFactor,
    int? intervalDays,
    DateTime? lastReviewedAt,
    DateTime? nextReviewAt,
    String? lastQuizVerdict,
    DateTime? lastQuizAt,
  }) {
    return Flashcard(
      id: id,
      deckId: deckId,
      familyId: familyId,
      front: front ?? this.front,
      back: back ?? this.back,
      sourceQuote: sourceQuote ?? this.sourceQuote,
      source: source ?? this.source,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      repetitions: repetitions ?? this.repetitions,
      easeFactor: easeFactor ?? this.easeFactor,
      intervalDays: intervalDays ?? this.intervalDays,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      lastQuizVerdict: lastQuizVerdict ?? this.lastQuizVerdict,
      lastQuizAt: lastQuizAt ?? this.lastQuizAt,
    );
  }
}
