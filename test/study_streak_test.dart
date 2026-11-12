import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/util/study_streak.dart';

void main() {
  test('counts consecutive active weekdays backwards from today', () {
    // 2026-05-06 is a Wednesday.
    final today = DateTime(2026, 5, 6);
    expect(
      computeStudyStreakDays(
        todayLocal: today,
        xpByDay: {
          '2026-05-06': 10,
          '2026-05-05': 5,
          '2026-05-04': 20,
        },
      ),
      3,
    );
  });

  test('weekend gap never breaks the streak', () {
    // 2026-05-06 (Wed) active, weekend before it (2026-05-02 Sat, 2026-05-03 Sun)
    // inactive, then 2026-05-01 (Fri) active. Streak should bridge the weekend.
    final today = DateTime(2026, 5, 6);
    expect(
      computeStudyStreakDays(
        todayLocal: today,
        xpByDay: {
          '2026-05-06': 10, // Wed
          '2026-05-05': 5, // Tue
          '2026-05-04': 5, // Mon
          // 2026-05-03 Sun: inactive, ignored
          // 2026-05-02 Sat: inactive, ignored
          '2026-05-01': 5, // Fri
        },
      ),
      4,
    );
  });

  test('weekend days count up when active', () {
    // 2026-05-04 is a Monday, active on both prior weekend days.
    final today = DateTime(2026, 5, 4);
    expect(
      computeStudyStreakDays(
        todayLocal: today,
        xpByDay: {
          '2026-05-04': 10, // Mon
          '2026-05-03': 5, // Sun
          '2026-05-02': 5, // Sat
          '2026-05-01': 5, // Fri
        },
      ),
      4,
    );
  });

  test('today without activity does not break streak, shows yesterday count', () {
    final today = DateTime(2026, 5, 6); // Wednesday, no xp yet today
    expect(
      computeStudyStreakDays(
        todayLocal: today,
        xpByDay: {
          '2026-05-05': 10,
          '2026-05-04': 5,
        },
      ),
      2,
    );
  });

  test('weekday gap (not weekend) breaks the streak', () {
    // 2026-05-07 Thu active, 2026-05-06 Wed inactive (weekday) -> breaks.
    final today = DateTime(2026, 5, 7);
    expect(
      computeStudyStreakDays(
        todayLocal: today,
        xpByDay: {
          '2026-05-07': 10,
          '2026-05-05': 10, // Tue, but Wed between is missing
        },
      ),
      1,
    );
  });

  test('handles year boundary', () {
    final today = DateTime(2027, 1, 1); // Friday
    expect(
      computeStudyStreakDays(
        todayLocal: today,
        xpByDay: {
          '2027-01-01': 5,
          '2026-12-31': 5,
          '2026-12-30': 5,
        },
      ),
      3,
    );
  });

  test('empty history gives zero', () {
    expect(
      computeStudyStreakDays(todayLocal: DateTime(2026, 5, 6), xpByDay: const {}),
      0,
    );
  });
}
