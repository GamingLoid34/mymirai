import 'package:flutter_test/flutter_test.dart';

import 'package:my_mirai/util/tts_sentence_offsets.dart';

void main() {
  group('computeSentenceOffsets', () {
    test('maps consecutive sentences to their character ranges', () {
      const text = 'Detta är första meningen. Detta är andra meningen.';
      final offsets = computeSentenceOffsets(text);
      expect(offsets.length, 2);
      expect(text.substring(offsets[0].start, offsets[0].end), 'Detta är första meningen.');
      expect(text.substring(offsets[1].start, offsets[1].end), 'Detta är andra meningen.');
    });

    test('offsets are sequential and non-overlapping', () {
      const text = 'En. Två. Tre meningar med lite mer text här för att undvika sammanslagning.';
      final offsets = computeSentenceOffsets(text);
      for (var i = 1; i < offsets.length; i++) {
        expect(offsets[i].start, greaterThanOrEqualTo(offsets[i - 1].end));
      }
    });

    test('empty text yields empty offsets', () {
      expect(computeSentenceOffsets(''), isEmpty);
    });
  });

  group('sentenceIndexForCharOffset', () {
    test('finds the sentence containing a given char offset', () {
      const text = 'Först. Sedan lite mer text i en andra mening här.';
      final offsets = computeSentenceOffsets(text);
      // Offset within the second sentence.
      final idx = sentenceIndexForCharOffset(offsets, text.indexOf('andra'));
      expect(idx, 1);
    });

    test('returns -1 for out-of-range offset', () {
      const text = 'En kort mening.';
      final offsets = computeSentenceOffsets(text);
      expect(sentenceIndexForCharOffset(offsets, 9999), -1);
    });

    test('returns first sentence for offset 0', () {
      const text = 'Första meningen är den här. Andra meningen kommer sen.';
      final offsets = computeSentenceOffsets(text);
      expect(sentenceIndexForCharOffset(offsets, 0), 0);
    });
  });
}
