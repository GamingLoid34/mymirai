import 'package:intl/intl.dart';

/// Konsekutiva kalenderdagar bakåt från [todayLocal] där lyssnad tid ≥ mål (Chunk I MVP).
int computeListeningStreakDays({
  required DateTime todayLocal,
  required int dailyGoalSeconds,
  required Map<String, int> listenedByYyyyMmDd,
}) {
  if (dailyGoalSeconds <= 0) return 0;
  var streak = 0;
  for (var i = 0; i < 366; i++) {
    final d = todayLocal.subtract(Duration(days: i));
    final id = DateFormat('yyyy-MM-dd').format(d);
    final secs = listenedByYyyyMmDd[id] ?? 0;
    if (secs >= dailyGoalSeconds) {
      streak++;
    } else {
      break;
    }
  }
  return streak;
}
