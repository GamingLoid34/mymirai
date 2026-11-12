import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/util/weekly_xp.dart';

void main() {
  test('sums xp for monday-sunday week containing the given day', () {
    // 2026-05-06 is a Wednesday. Week is Mon 2026-05-04 .. Sun 2026-05-10.
    final total = weeklyXpTotal(
      dayInWeek: DateTime(2026, 5, 6),
      xpByDay: {
        '2026-05-04': 10,
        '2026-05-05': 5,
        '2026-05-06': 20,
        '2026-05-03': 999, // previous week, must be excluded
        '2026-05-11': 999, // next week, must be excluded
      },
    );
    expect(total, 35);
  });

  test('handles month boundary correctly', () {
    // 2026-06-01 is a Monday. Week is Mon 2026-06-01 .. Sun 2026-06-07.
    final total = weeklyXpTotal(
      dayInWeek: DateTime(2026, 6, 3),
      xpByDay: {
        '2026-05-31': 999, // previous week (Sunday before), excluded
        '2026-06-01': 15,
        '2026-06-07': 25,
      },
    );
    expect(total, 40);
  });

  test('empty map gives zero', () {
    expect(
      weeklyXpTotal(dayInWeek: DateTime(2026, 5, 6), xpByDay: const {}),
      0,
    );
  });

  test('breakdown returns seven days starting monday', () {
    final days = weeklyXpBreakdown(
      dayInWeek: DateTime(2026, 5, 6),
      xpByDay: {'2026-05-04': 10},
    );
    expect(days.length, 7);
    expect(days.first.day, DateTime(2026, 5, 4));
    expect(days.first.xp, 10);
    expect(days.last.day, DateTime(2026, 5, 10));
    expect(days.last.xp, 0);
  });
}
