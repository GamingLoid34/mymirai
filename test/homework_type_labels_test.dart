import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/util/homework_type_labels.dart';

void main() {
  group('homeworkTypeExplanation', () {
    test('explains text', () {
      expect(
        homeworkTypeExplanation('text'),
        'Text → sammanfattning att lyssna på + AI-frågor att träna med.',
      );
    });

    test('explains vocabulary', () {
      expect(
        homeworkTypeExplanation('vocabulary'),
        'Glosor → förhörskort per ord, redo att förhöras på.',
      );
    });

    test('explains math', () {
      expect(
        homeworkTypeExplanation('math'),
        'Matte → uppgifterna listas med förklaringar och övningsvarianter.',
      );
    });

    test('unknown type falls back to text explanation', () {
      expect(
        homeworkTypeExplanation('unknown'),
        'Text → sammanfattning att lyssna på + AI-frågor att träna med.',
      );
    });
  });

  group('homeworkTypeLabel', () {
    test('labels vocabulary', () {
      expect(homeworkTypeLabel('vocabulary'), 'Glosor');
    });

    test('labels math', () {
      expect(homeworkTypeLabel('math'), 'Matte');
    });

    test('labels text', () {
      expect(homeworkTypeLabel('text'), 'Text');
    });

    test('unknown type falls back to Text', () {
      expect(homeworkTypeLabel('unknown'), 'Text');
    });
  });
}
