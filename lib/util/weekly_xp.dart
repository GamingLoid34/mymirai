import 'package:intl/intl.dart';

/// Summerar `xpByDay` för veckan (måndag–söndag) som innehåller [dayInWeek].
int weeklyXpTotal({
  required DateTime dayInWeek,
  required Map<String, int> xpByDay,
}) {
  final monday = _mondayOf(dayInWeek);
  var sum = 0;
  for (var i = 0; i < 7; i++) {
    final d = monday.add(Duration(days: i));
    final id = DateFormat('yyyy-MM-dd').format(d);
    sum += xpByDay[id] ?? 0;
  }
  return sum;
}

/// De sju dagarna (måndag–söndag) i veckan som innehåller [dayInWeek), med XP var och en.
List<({DateTime day, int xp})> weeklyXpBreakdown({
  required DateTime dayInWeek,
  required Map<String, int> xpByDay,
}) {
  final monday = _mondayOf(dayInWeek);
  return [
    for (var i = 0; i < 7; i++)
      (
        day: monday.add(Duration(days: i)),
        xp: xpByDay[DateFormat('yyyy-MM-dd').format(monday.add(Duration(days: i)))] ?? 0,
      ),
  ];
}

DateTime _mondayOf(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  return date.subtract(Duration(days: date.weekday - 1));
}
