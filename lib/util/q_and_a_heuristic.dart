/// Heuristik för Q/A-formaterat läxmaterialet (roadmap v5).
bool looksLikeQAndA(String text) {
  final svarRegex =
      RegExp(r'^\s*Svar\s*:', multiLine: true, caseSensitive: false);
  final matches = svarRegex.allMatches(text).length;
  return matches >= 3;
}
