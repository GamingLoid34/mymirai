import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/util/q_and_a_heuristic.dart';

void main() {
  group('looksLikeQAndA', () {
    test('true when at least three Svar: markers', () {
      const text = '''
Fråga 1?
Svar: Ett.

Fråga 2?
svar: Två.

Fråga 3?
 Svar :
Tre stycken.
''';
      expect(looksLikeQAndA(text), true);
    });

    test('false för vanlig löptext utan tre svar', () {
      const text = '''Vikingatiden varade länge.

Svar: bara en gång.''';
      expect(looksLikeQAndA(text), false);
    });
  });
}
