import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/util/listening_streak.dart';

void main() {
  test('streak counts consecutive goal days backwards from today', () {
    final today = DateTime(2026, 5, 1);
    expect(
      computeListeningStreakDays(
        todayLocal: today,
        dailyGoalSeconds: 1800,
        listenedByYyyyMmDd: {
          '2026-05-01': 2000,
          '2026-04-30': 1800,
          '2026-04-29': 500,
        },
      ),
      2,
    );
  });

  test('streak stops at first incomplete day including today', () {
    final today = DateTime(2026, 5, 1);
    expect(
      computeListeningStreakDays(
        todayLocal: today,
        dailyGoalSeconds: 100,
        listenedByYyyyMmDd: {
          '2026-05-01': 99,
          '2026-04-30': 999,
        },
      ),
      0,
    );
  });
}
