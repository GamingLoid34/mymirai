import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/models/flashcard.dart';
import 'package:my_mirai/services/spaced_repetition.dart';
import 'package:my_mirai/util/session_summary.dart';

Flashcard _card(String id, String front) => Flashcard(
      id: id,
      deckId: 'deck-1',
      familyId: 'fam-1',
      front: front,
      back: 'back of $front',
      source: FlashcardSource.manual,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('buildSessionSummary', () {
    test('handles empty results and empty cards', () {
      final summary = buildSessionSummary(
        cards: [],
        results: {},
      );

      expect(summary.total, 0);
      expect(summary.satDirekt, 0);
      expect(summary.comebackFronts, isEmpty);
      expect(summary.truncated, isFalse);
    });

    test('all correct (good and easy)', () {
      final cards = [
        _card('1', 'hund'),
        _card('2', 'katt'),
        _card('3', 'fågel'),
      ];
      final results = {
        '1': ReviewQuality.good,
        '2': ReviewQuality.easy,
        '3': ReviewQuality.good,
      };

      final summary = buildSessionSummary(cards: cards, results: results);

      expect(summary.total, 3);
      expect(summary.satDirekt, 3);
      expect(summary.comebackFronts, isEmpty);
      expect(summary.truncated, isFalse);
    });

    test('mixed results preserves order in comebackFronts', () {
      final cards = [
        _card('1', 'springa'),
        _card('2', 'hoppa'),
        _card('3', 'simma'),
        _card('4', 'flyga'),
      ];
      final results = {
        '1': ReviewQuality.again,
        '2': ReviewQuality.good,
        '3': ReviewQuality.hard,
        '4': ReviewQuality.easy,
      };

      final summary = buildSessionSummary(cards: cards, results: results);

      expect(summary.total, 4);
      expect(summary.satDirekt, 2);
      expect(summary.comebackFronts, ['springa', 'simma']);
      expect(summary.truncated, isFalse);
    });

    test('truncates comebacks to max 5 and flags truncated', () {
      final cards = [
        _card('1', 'ett'),
        _card('2', 'två'),
        _card('3', 'tre'),
        _card('4', 'fyra'),
        _card('5', 'fem'),
        _card('6', 'sex'),
        _card('7', 'sju'),
      ];
      final results = {
        '1': ReviewQuality.again,
        '2': ReviewQuality.hard,
        '3': ReviewQuality.again,
        '4': ReviewQuality.hard,
        '5': ReviewQuality.again,
        '6': ReviewQuality.hard,
        '7': ReviewQuality.good,
      };

      final summary = buildSessionSummary(cards: cards, results: results);

      expect(summary.total, 7);
      expect(summary.satDirekt, 1);
      expect(summary.comebackFronts, ['ett', 'två', 'tre', 'fyra', 'fem']);
      expect(summary.truncated, isTrue);
    });
  });
}
