import '../services/tts_service.dart';

/// Teckenoffset [start, end) i [fullText] för varje mening från
/// [TtsService.splitSentences]. Sekventiell `indexOf` — meningarna antas
/// förekomma i samma ordning och (i huvudsak) oförändrade i källtexten.
List<({int start, int end})> computeSentenceOffsets(String fullText) {
  final sentences = TtsService.splitSentences(fullText);
  final offsets = <({int start, int end})>[];
  var searchFrom = 0;
  for (final sentence in sentences) {
    final idx = fullText.indexOf(sentence, searchFrom);
    if (idx < 0) {
      // Meningen hittades inte (t.ex. sammanslagning normaliserade whitespace)
      // — bäst-effort: fortsätt utan offset för den här meningen.
      offsets.add((start: searchFrom, end: searchFrom));
      continue;
    }
    final end = idx + sentence.length;
    offsets.add((start: idx, end: end));
    searchFrom = end;
  }
  return offsets;
}

/// Index i [offsets] vars intervall innehåller [charOffset], eller -1.
int sentenceIndexForCharOffset(
  List<({int start, int end})> offsets,
  int charOffset,
) {
  for (var i = 0; i < offsets.length; i++) {
    final o = offsets[i];
    if (charOffset >= o.start && charOffset < o.end) return i;
  }
  return -1;
}
