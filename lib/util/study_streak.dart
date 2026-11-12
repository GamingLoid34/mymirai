import 'package:intl/intl.dart';

/// Konsekutiva dagar med aktivitet (xp > 0), bakåt från [todayLocal].
///
/// Förlåtande mekanik: lördag/söndag bryter aldrig streaken (men räknas
/// upp om aktiva), och dagens dag räknas inte som brytande om den ännu
/// är utan aktivitet — visar då gårdagens streak.
int computeStudyStreakDays({
  required DateTime todayLocal,
  required Map<String, int> xpByDay,
}) {
  bool activeOn(DateTime d) {
    final id = DateFormat('yyyy-MM-dd').format(d);
    return (xpByDay[id] ?? 0) > 0;
  }

  var streak = 0;
  var cursor = DateTime(todayLocal.year, todayLocal.month, todayLocal.day);
  var isFirstDay = true;

  for (var i = 0; i < 366; i++) {
    final isWeekend = cursor.weekday == DateTime.saturday || cursor.weekday == DateTime.sunday;
    final active = activeOn(cursor);

    if (active) {
      streak++;
    } else if (isFirstDay || isWeekend) {
      // Dagens dag utan aktivitet ännu, eller en helgdag utan aktivitet:
      // bryter inte streaken, räknas bara inte upp.
    } else {
      break;
    }

    isFirstDay = false;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}
