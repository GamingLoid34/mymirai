import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/models/homework_item.dart';
import 'package:my_mirai/util/home_picker.dart';

HomeworkItem _hw({
  required String id,
  required HomeworkStatus status,
  DateTime? dueAt,
  DateTime? createdAt,
}) {
  final base = createdAt ?? DateTime(2026, 6, 1);
  return HomeworkItem(
    id: id,
    familyId: 'fam',
    assignedToUserId: 'u1',
    subject: 'Matte',
    title: id,
    dueAt: dueAt,
    status: status,
    createdAt: base,
    updatedAt: base,
  );
}

void main() {
  /// Onsdag 10 juni 2026
  final now = DateTime(2026, 6, 10, 14, 30);

  test('pickNextHomework null when no active', () {
    expect(
      pickNextHomework(
        [
          _hw(id: 'a', status: HomeworkStatus.done, dueAt: DateTime(2026, 6, 11)),
        ],
        now,
      ),
      isNull,
    );
    expect(pickNextHomework(const [], now), isNull);
  });

  test('pickNext prefers due today-or-earlier before tomorrow', () {
    final n = pickNextHomework([
      _hw(id: 'tomorrow', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 11)),
      _hw(id: 'past', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 8)),
      _hw(id: 'today', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 10)),
    ], now);
    expect(n?.id, 'past');
  });

  test('pickNext among overdue picks earliest deadline', () {
    final n = pickNextHomework([
      _hw(id: 'old', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 1)),
      _hw(id: 'mid', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 5)),
    ], now);
    expect(n?.id, 'old');
  });

  test('pickNext tomorrow tier when nothing due through today', () {
    final n = pickNextHomework([
      _hw(id: 'week', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 17)),
      _hw(id: 'tom', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 11)),
    ], now);
    expect(n?.id, 'tom');
  });

  test('pickNext within 7 days after tomorrow tier', () {
    final n = pickNextHomework([
      _hw(id: 'far', status: HomeworkStatus.todo, dueAt: DateTime(2026, 7, 20)),
      _hw(
        id: 'soon',
        status: HomeworkStatus.todo,
        dueAt: DateTime(2026, 6, 15),
      ),
      _hw(id: 'later', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 16)),
    ], now);
    expect(n?.id, 'soon');
  });

  test('pickNext fallback most recently created', () {
    final n = pickNextHomework([
      _hw(
        id: 'a',
        status: HomeworkStatus.todo,
        createdAt: DateTime(2026, 6, 1),
      ),
      _hw(
        id: 'b',
        status: HomeworkStatus.todo,
        createdAt: DateTime(2026, 6, 9),
      ),
    ], now);
    expect(n?.id, 'b');
  });

  test('pickHomeForHome empty list gives next null', () {
    final pick = pickHomeForHome(const [], now);
    expect(pick.next, isNull);
    expect(pick.today, isEmpty);
    expect(pick.week, isEmpty);
  });

  test('pickHomeForHome only overdue chooses overdue as next', () {
    final pick = pickHomeForHome([
      _hw(id: 'overdue', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 8)),
    ], now);
    expect(pick.next?.id, 'overdue');
    expect(pick.today, isEmpty);
    expect(pick.week, isEmpty);
  });

  test('pickHomeForHome only today chooses today as next', () {
    final pick = pickHomeForHome([
      _hw(id: 'today', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 10)),
    ], now);
    expect(pick.next?.id, 'today');
    expect(pick.today, isEmpty);
    expect(pick.week, isEmpty);
  });

  test('pickHomeForHome only tomorrow chooses tomorrow as next', () {
    final pick = pickHomeForHome([
      _hw(id: 'tom', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 11)),
    ], now);
    expect(pick.next?.id, 'tom');
    expect(pick.today, isEmpty);
    expect(pick.week, isEmpty);
  });

  test('pickHomeForHome overdue + today + tomorrow picks overdue first', () {
    final pick = pickHomeForHome([
      _hw(id: 'tom', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 11)),
      _hw(id: 'today', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 10)),
      _hw(id: 'overdue', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 9)),
    ], now);
    expect(pick.next?.id, 'overdue');
    expect(pick.today.map((e) => e.id), orderedEquals(['today', 'tom']));
    expect(pick.week, isEmpty);
  });

  test('pickHomeForHome ten items in week splits into today and week', () {
    final picks = pickHomeForHome([
      _hw(id: 'a', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 10)),
      _hw(id: 'b', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 11)),
      _hw(id: 'c', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 12)),
      _hw(id: 'd', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 12)),
      _hw(id: 'e', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 13)),
      _hw(id: 'f', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 13)),
      _hw(id: 'g', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 14)),
      _hw(id: 'h', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 15)),
      _hw(id: 'i', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 16)),
      _hw(id: 'j', status: HomeworkStatus.todo, dueAt: DateTime(2026, 6, 17)),
    ], now);

    expect(picks.next?.id, 'a');
    expect(picks.today.map((e) => e.id).toList(), orderedEquals(['b']));
    expect(
      picks.week.map((e) => e.id).toList(),
      orderedEquals(['c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']),
    );
  });
}
