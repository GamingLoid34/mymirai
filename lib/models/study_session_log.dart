import 'package:cloud_firestore/cloud_firestore.dart';

/// Logg över ett genomfört förhör/repetitionspass för föräldrainsyn och historik (AP8).
class StudySessionLog {
  const StudySessionLog({
    required this.id,
    this.homeworkId,
    this.deckId,
    required this.userId,
    required this.completedAt,
    required this.totalCards,
    required this.correctCards,
    required this.incorrectCards,
    this.missedFronts = const [],
    required this.durationSeconds,
    required this.mode,
  });

  final String id;
  final String? homeworkId;
  final String? deckId;
  final String userId;
  final DateTime completedAt;
  final int totalCards;
  final int correctCards;
  final int incorrectCards;
  final List<String> missedFronts;
  final int durationSeconds;

  /// 'simplified' (Kunde/Kunde inte), 'standard' (4 knappar SM-2), 'written' (skriftligt)
  final String mode;

  Map<String, dynamic> toMap() => {
        'id': id,
        if (homeworkId != null) 'homeworkId': homeworkId,
        if (deckId != null) 'deckId': deckId,
        'userId': userId,
        'completedAt': completedAt.toIso8601String(),
        'totalCards': totalCards,
        'correctCards': correctCards,
        'incorrectCards': incorrectCards,
        'missedFronts': missedFronts,
        'durationSeconds': durationSeconds,
        'mode': mode,
      };

  Map<String, dynamic> toFirestore() => {
        if (homeworkId != null) 'homeworkId': homeworkId,
        if (deckId != null) 'deckId': deckId,
        'userId': userId,
        'completedAt': Timestamp.fromDate(completedAt),
        'totalCards': totalCards,
        'correctCards': correctCards,
        'incorrectCards': incorrectCards,
        'missedFronts': missedFronts,
        'durationSeconds': durationSeconds,
        'mode': mode,
      };

  factory StudySessionLog.fromMap(Map<String, dynamic> map, [String? docId]) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    final rawMissed = map['missedFronts'];
    final missedList = <String>[];
    if (rawMissed is List) {
      for (final item in rawMissed) {
        if (item is String && item.trim().isNotEmpty) {
          missedList.add(item.trim());
        }
      }
    }

    return StudySessionLog(
      id: docId ?? map['id'] as String? ?? '',
      homeworkId: map['homeworkId'] as String?,
      deckId: map['deckId'] as String?,
      userId: map['userId'] as String? ?? '',
      completedAt: parseDate(map['completedAt']),
      totalCards: (map['totalCards'] as num?)?.toInt() ?? 0,
      correctCards: (map['correctCards'] as num?)?.toInt() ?? 0,
      incorrectCards: (map['incorrectCards'] as num?)?.toInt() ?? 0,
      missedFronts: missedList,
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      mode: map['mode'] as String? ?? 'simplified',
    );
  }

  factory StudySessionLog.fromFirestore(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>? ?? {};
    return StudySessionLog.fromMap(data, snap.id);
  }
}
