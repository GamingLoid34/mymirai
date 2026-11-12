/// En fråga i barnläget ”Gör ett test” (chunk G).
enum TestQuestionType { open, multipleChoice }

class TestQuestionItem {
  const TestQuestionItem({
    required this.cardId,
    required this.deckId,
    required this.front,
    required this.type,
    this.options,
    this.correctIndex,
    this.sourceQuote,
  });

  final String cardId;
  final String deckId;
  final String front;
  final TestQuestionType type;
  final List<String>? options;
  final int? correctIndex;
  /// Ursprungskortets källcitat (Chunk X), om det finns.
  final String? sourceQuote;

  static TestQuestionItem fromCloudMap(Map<String, dynamic> m) {
    final typeStr = (m['type'] as String?)?.trim() ?? '';
    final cardId = (m['cardId'] as String?)?.trim() ?? '';
    final deckId = (m['deckId'] as String?)?.trim() ?? '';
    final front = (m['front'] as String?)?.trim() ?? '';
    final sqRaw = m['sourceQuote'];
    final sourceQuote =
        sqRaw is String && sqRaw.trim().isNotEmpty ? sqRaw.trim() : null;
    if (cardId.isEmpty || deckId.isEmpty || front.isEmpty) {
      throw FormatException('Ogiltigt testfrågeobjekt från servern.');
    }
    if (typeStr == 'multiple_choice') {
      final rawOpts = m['options'];
      if (rawOpts is! List || rawOpts.length != 4) {
        throw FormatException('Ogiltiga flervalalternativ.');
      }
      final options = rawOpts.map((e) => (e as String?)?.trim() ?? '').toList();
      final ci = (m['correctIndex'] as num?)?.toInt();
      if (ci == null || ci < 0 || ci > 3 || options.any((s) => s.isEmpty)) {
        throw FormatException('Ogiltig correctIndex eller tomma alternativ.');
      }
      return TestQuestionItem(
        cardId: cardId,
        deckId: deckId,
        front: front,
        type: TestQuestionType.multipleChoice,
        options: options,
        correctIndex: ci,
        sourceQuote: sourceQuote,
      );
    }
    return TestQuestionItem(
      cardId: cardId,
      deckId: deckId,
      front: front,
      type: TestQuestionType.open,
      sourceQuote: sourceQuote,
    );
  }
}
