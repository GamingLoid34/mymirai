import 'package:flutter_test/flutter_test.dart';

import 'package:my_mirai/models/document.dart';
import 'package:my_mirai/util/continue_listening.dart';

void main() {
  group('computeReadingProgress', () {
    test('clamps to 0.0 when duration is zero', () {
      expect(
        computeReadingProgress(position: Duration.zero, duration: Duration.zero),
        0.0,
      );
    });

    test('computes fraction of position over duration', () {
      expect(
        computeReadingProgress(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 120),
        ),
        0.25,
      );
    });

    test('clamps to 1.0 when position exceeds duration', () {
      expect(
        computeReadingProgress(
          position: const Duration(seconds: 200),
          duration: const Duration(seconds: 120),
        ),
        1.0,
      );
    });
  });

  group('pickContinueListening', () {
    final stamp = DateTime(2026, 1, 1);

    UserDocument doc({
      required String id,
      double readingProgress = 0.0,
      DateTime? lastReadAt,
    }) {
      return UserDocument(
        id: id,
        ownerUid: 'u1',
        title: id,
        sourceType: 'text',
        readingProgress: readingProgress,
        lastReadAt: lastReadAt,
        createdAt: stamp,
        updatedAt: stamp,
      );
    }

    test('returns null for empty list', () {
      expect(pickContinueListening(const []), isNull);
    });

    test('excludes documents at or below 2% progress', () {
      final docs = [
        doc(id: 'a', readingProgress: 0.02, lastReadAt: stamp),
        doc(id: 'b', readingProgress: 0.0, lastReadAt: stamp),
      ];
      expect(pickContinueListening(docs), isNull);
    });

    test('excludes documents at or above 97% progress', () {
      final docs = [
        doc(id: 'a', readingProgress: 0.97, lastReadAt: stamp),
        doc(id: 'b', readingProgress: 1.0, lastReadAt: stamp),
      ];
      expect(pickContinueListening(docs), isNull);
    });

    test('excludes documents without lastReadAt', () {
      final docs = [doc(id: 'a', readingProgress: 0.5, lastReadAt: null)];
      expect(pickContinueListening(docs), isNull);
    });

    test('picks the document with most recent lastReadAt among eligible', () {
      final docs = [
        doc(id: 'old', readingProgress: 0.5, lastReadAt: stamp),
        doc(
          id: 'newer',
          readingProgress: 0.6,
          lastReadAt: stamp.add(const Duration(days: 1)),
        ),
        doc(id: 'ineligible', readingProgress: 0.99, lastReadAt: stamp.add(const Duration(days: 5))),
      ];
      expect(pickContinueListening(docs)?.id, 'newer');
    });
  });
}
