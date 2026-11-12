import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/models/study_session_log.dart';

void main() {
  group('StudySessionLog', () {
    test('serializes to map and back', () {
      final now = DateTime(2026, 9, 5, 14, 30);
      final log = StudySessionLog(
        id: 'log-1',
        homeworkId: 'hw-123',
        deckId: 'deck-456',
        userId: 'user-789',
        completedAt: now,
        totalCards: 10,
        correctCards: 8,
        incorrectCards: 2,
        missedFronts: const ['dog', 'cat'],
        durationSeconds: 120,
        mode: 'simplified',
      );

      final map = log.toMap();
      final restored = StudySessionLog.fromMap(map, 'log-1');

      expect(restored.id, 'log-1');
      expect(restored.homeworkId, 'hw-123');
      expect(restored.deckId, 'deck-456');
      expect(restored.userId, 'user-789');
      expect(restored.completedAt, now);
      expect(restored.totalCards, 10);
      expect(restored.correctCards, 8);
      expect(restored.incorrectCards, 2);
      expect(restored.missedFronts, ['dog', 'cat']);
      expect(restored.durationSeconds, 120);
      expect(restored.mode, 'simplified');
    });

    test('handles empty or missing optional fields gracefully', () {
      final map = <String, dynamic>{
        'userId': 'user-1',
        'totalCards': 5,
        'correctCards': 5,
      };

      final log = StudySessionLog.fromMap(map, 'log-2');
      expect(log.id, 'log-2');
      expect(log.homeworkId, isNull);
      expect(log.deckId, isNull);
      expect(log.incorrectCards, 0);
      expect(log.missedFronts, isEmpty);
      expect(log.durationSeconds, 0);
      expect(log.mode, 'simplified');
    });
  });
}
