import '../models/homework_item.dart';

/// Kalenderdatum (lokal dag) för en läxa.
DateTime homeworkDay(DateTime dt) =>
    DateTime(dt.year, dt.month, dt.day);

bool homeworkIsActive(HomeworkItem h) =>
    h.status != HomeworkStatus.done && h.status != HomeworkStatus.archived;

int _cmpDueAscThenCreatedAsc(HomeworkItem a, HomeworkItem b) {
  final da = a.dueAt;
  final db = b.dueAt;
  if (da != null && db != null) {
    final byDay = homeworkDay(da).compareTo(homeworkDay(db));
    if (byDay != 0) return byDay;
    return a.createdAt.compareTo(b.createdAt);
  }
  if (da != null) return -1;
  if (db != null) return 1;
  return a.createdAt.compareTo(b.createdAt);
}

int _cmpDueAscNullsLast(HomeworkItem a, HomeworkItem b) {
  final da = a.dueAt;
  final db = b.dueAt;
  if (da != null && db != null) {
    final byDay = homeworkDay(da).compareTo(homeworkDay(db));
    if (byDay != 0) return byDay;
    return a.createdAt.compareTo(b.createdAt);
  }
  if (da != null) return -1;
  if (db != null) return 1;
  return b.createdAt.compareTo(a.createdAt);
}

/// Tier 22–25 (roadmap Chunk L): en läxa att lyfta högst på Hem.
HomeworkItem? pickNextHomework(List<HomeworkItem> items, DateTime now) {
  final today = homeworkDay(now);
  final tomorrow = today.add(const Duration(days: 1));
  final weekEndInclusive = today.add(const Duration(days: 7));

  final active =
      [for (final h in items) if (homeworkIsActive(h)) h];
  if (active.isEmpty) return null;

  HomeworkItem? firstSorted(List<HomeworkItem> src) {
    if (src.isEmpty) return null;
    src.sort(_cmpDueAscThenCreatedAsc);
    return src.first;
  }

  final tier22 = active.where((h) {
    if (h.dueAt == null) return false;
    return !homeworkDay(h.dueAt!).isAfter(today);
  }).toList();
  final n22 = firstSorted(tier22);
  if (n22 != null) return n22;

  final tier23 = active.where((h) {
    if (h.dueAt == null) return false;
    return homeworkDay(h.dueAt!) == tomorrow;
  }).toList();
  final n23 = firstSorted(tier23);
  if (n23 != null) return n23;

  final tier24 = active.where((h) {
    if (h.dueAt == null) return false;
    final d = homeworkDay(h.dueAt!);
    return d.isAfter(tomorrow) && !d.isAfter(weekEndInclusive);
  }).toList();
  final n24 = firstSorted(tier24);
  if (n24 != null) return n24;

  active.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return active.first;
}

class HomeSelection {
  const HomeSelection({
    required this.next,
    required this.today,
    required this.week,
  });

  final HomeworkItem? next;
  final List<HomeworkItem> today;
  final List<HomeworkItem> week;
}

/// Delar in aktiva läxor för Hem med innehåll först.
HomeSelection pickHomeForHome(List<HomeworkItem> items, DateTime now) {
  final next = pickNextHomework(items, now);
  final today = homeworkDay(now);
  final tomorrow = today.add(const Duration(days: 1));
  final weekStart = today.add(const Duration(days: 2));
  final weekLast = today.add(const Duration(days: 7));

  final active =
      [for (final h in items) if (homeworkIsActive(h)) h];
  final nextId = next?.id;

  final todayItems = <HomeworkItem>[];
  for (final h in active) {
    if (h.id == nextId) continue;
    if (h.dueAt == null) continue;
    final d = homeworkDay(h.dueAt!);
    if (d.isAfter(tomorrow)) continue;
    todayItems.add(h);
  }
  todayItems.sort(_cmpDueAscThenCreatedAsc);
  final todayTrimmed = todayItems.take(5).toList(growable: false);

  final skipIds = <String>{for (final h in todayTrimmed) h.id};
  final nId = nextId;
  if (nId != null) skipIds.add(nId);

  final weekItems = <HomeworkItem>[];
  for (final h in active) {
    if (skipIds.contains(h.id)) continue;
    if (h.dueAt == null) continue;
    final d = homeworkDay(h.dueAt!);
    if (d.isBefore(weekStart)) continue;
    if (d.isAfter(weekLast)) continue;
    weekItems.add(h);
  }
  weekItems.sort(_cmpDueAscNullsLast);

  return HomeSelection(
    next: next,
    today: todayTrimmed,
    week: weekItems,
  );
}
