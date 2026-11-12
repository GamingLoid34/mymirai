import 'package:flutter_test/flutter_test.dart';

import 'package:my_mirai/models/document.dart';
import 'package:my_mirai/services/listening_queue.dart';

void main() {
  UserDocument doc({
    required String id,
    double readingProgress = 0.0,
    String? summary,
    String? extractedText,
    DateTime? updatedAt,
  }) {
    return UserDocument(
      id: id,
      ownerUid: 'u1',
      title: id,
      sourceType: 'text',
      readingProgress: readingProgress,
      summary: summary,
      extractedText: extractedText,
      updatedAt: updatedAt,
    );
  }

  test('excludes documents at or above 97% progress', () {
    final docs = [
      doc(id: 'a', readingProgress: 0.97, summary: 's', updatedAt: DateTime(2026, 1, 1)),
      doc(id: 'b', readingProgress: 1.0, summary: 's', updatedAt: DateTime(2026, 1, 1)),
    ];
    expect(buildListeningQueue(docs), isEmpty);
  });

  test('excludes documents without listenable text', () {
    final docs = [doc(id: 'a', updatedAt: DateTime(2026, 1, 1))];
    expect(buildListeningQueue(docs), isEmpty);
  });

  test('includes documents with only extractedText (no summary)', () {
    final docs = [
      doc(id: 'a', extractedText: 'text here', updatedAt: DateTime(2026, 1, 1)),
    ];
    expect(buildListeningQueue(docs).map((d) => d.id).toList(), ['a']);
  });

  test('sorts newest updatedAt first', () {
    final docs = [
      doc(id: 'old', summary: 's', updatedAt: DateTime(2026, 1, 1)),
      doc(id: 'new', summary: 's', updatedAt: DateTime(2026, 1, 5)),
      doc(id: 'mid', summary: 's', updatedAt: DateTime(2026, 1, 3)),
    ];
    expect(
      buildListeningQueue(docs).map((d) => d.id).toList(),
      ['new', 'mid', 'old'],
    );
  });

  test('documents without updatedAt sort last', () {
    final docs = [
      doc(id: 'noDate', summary: 's'),
      doc(id: 'hasDate', summary: 's', updatedAt: DateTime(2026, 1, 1)),
    ];
    expect(
      buildListeningQueue(docs).map((d) => d.id).toList(),
      ['hasDate', 'noDate'],
    );
  });
}
