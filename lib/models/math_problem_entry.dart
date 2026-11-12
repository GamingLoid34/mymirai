class MathProblemEntry {
  const MathProblemEntry({
    required this.originalText,
    this.explanation,
    this.variants = const [],
  });

  final String originalText;
  final String? explanation;

  /// Säkra siffervarianter (Chunk O).
  final List<String> variants;

  Map<String, dynamic> toMap() => {
        'originalText': originalText,
        if (explanation != null && explanation!.trim().isNotEmpty)
          'explanation': explanation,
        if (variants.isNotEmpty) 'variants': variants,
      };

  static MathProblemEntry fromMap(Map<String, dynamic> m) {
    final rawV = m['variants'];
    final vars = <String>[];
    if (rawV is List) {
      for (final e in rawV) {
        if (e is String && e.trim().isNotEmpty) vars.add(e.trim());
      }
    }
    return MathProblemEntry(
      originalText: m['originalText'] as String? ?? '',
      explanation: m['explanation'] as String?,
      variants: vars,
    );
  }

  MathProblemEntry copyWith({
    String? originalText,
    String? explanation,
    List<String>? variants,
  }) =>
      MathProblemEntry(
        originalText: originalText ?? this.originalText,
        explanation: explanation ?? this.explanation,
        variants: variants ?? this.variants,
      );
}
