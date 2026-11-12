import 'package:cloud_firestore/cloud_firestore.dart';

class FlashcardDeck {
  const FlashcardDeck({
    required this.id,
    required this.familyId,
    required this.homeworkId,
    required this.title,
    this.subject,
    this.cardSource,
    required this.createdAt,
    required this.updatedAt,
    required this.cardCount,
  });

  final String id;
  final String familyId;
  final String homeworkId;
  final String title;
  final String? subject;
  /// `extracted` när frågorna kommer direkt ur materialet (v5).
  final String? cardSource;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int cardCount;

  static FlashcardDeck fromMap(String id, Map<String, dynamic> data) {
    final created = data['createdAt'];
    final updated = data['updatedAt'];
    final csRaw = data['cardSource'];
    final cs = csRaw is String && csRaw.trim().isNotEmpty ? csRaw.trim() : null;

    return FlashcardDeck(
      id: id,
      familyId: data['familyId'] as String? ?? '',
      homeworkId: data['homeworkId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      subject: data['subject'] as String?,
      cardSource: cs,
      createdAt:
          created is Timestamp ? created.toDate() : DateTime.now(),
      updatedAt:
          updated is Timestamp ? updated.toDate() : DateTime.now(),
      cardCount: (data['cardCount'] as num?)?.toInt() ?? 0,
    );
  }

  static FlashcardDeck fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return FlashcardDeck.fromMap(doc.id, data);
  }

  Map<String, dynamic> toMap() => {
        'familyId': familyId,
        'homeworkId': homeworkId,
        'title': title,
        'subject': subject,
        if (cardSource != null && cardSource!.trim().isNotEmpty)
          'cardSource': cardSource!.trim(),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'cardCount': cardCount,
      };
}
