class VocabularyEntry {
  const VocabularyEntry({
    required this.term,
    required this.translation,
    this.example,
  });

  final String term;
  final String translation;
  final String? example;

  Map<String, dynamic> toMap() => {
        'term': term,
        'translation': translation,
        if (example != null && example!.trim().isNotEmpty) 'example': example,
      };

  static VocabularyEntry fromMap(Map<String, dynamic> m) {
    return VocabularyEntry(
      term: m['term'] as String? ?? '',
      translation: m['translation'] as String? ?? '',
      example: m['example'] as String?,
    );
  }

  bool get isValid =>
      term.trim().isNotEmpty && translation.trim().isNotEmpty;
}
