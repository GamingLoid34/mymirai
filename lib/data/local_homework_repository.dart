import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/homework_item.dart';
import 'homework_repository.dart';

/// En bekräftad import skrivs i sin helhet innan läxlistan uppdateras.
class LocalHomeworkRepository implements HomeworkRepository {
  LocalHomeworkRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'my_mirai.homework.v1';
  final _changes = StreamController<void>.broadcast();
  Future<void> _pending = Future.value();

  List<HomeworkItem> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    final list =
        jsonDecode(
              raw,
              reviver: (_, value) {
                if (value is Map &&
                    value.length == 1 &&
                    value['timestamp'] is int) {
                  return Timestamp.fromMillisecondsSinceEpoch(
                    value['timestamp'] as int,
                  );
                }
                return value;
              },
            )
            as List;
    return [for (final m in list) HomeworkItem.fromData(m['id'] as String, m)];
  }

  Future<T> _write<T>(T Function(List<HomeworkItem>) change) {
    final result = _pending.then((_) async {
      final items = _read();
      final value = change(items);
      final encoded = jsonEncode(
        [
          for (final item in items)
            {
              ...item.toFirestoreCreate(now: item.createdAt),
              'updatedAt': Timestamp.fromDate(item.updatedAt),
              'id': item.id,
            },
        ],
        toEncodable: (value) => {
          'timestamp': (value as Timestamp).millisecondsSinceEpoch,
        },
      );
      if (!await _prefs.setString(_key, encoded)) {
        await _prefs.reload();
        throw StateError('Läxorna kunde inte sparas på enheten.');
      }
      _changes.add(null);
      return value;
    });
    _pending = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) async {
        await _prefs.reload();
      },
    );
    return result;
  }

  @override
  Stream<List<HomeworkItem>> watchForFamily({
    required String familyId,
    String? assignedToUserId,
  }) {
    return Stream.multi((listener) {
      void emit() {
        try {
          final items =
              _read()
                  .where(
                    (h) =>
                        h.familyId == familyId &&
                        (assignedToUserId == null ||
                            h.assignedToUserId == assignedToUserId),
                  )
                  .toList()
                ..sort((a, b) {
                  if (a.dueAt == null && b.dueAt == null) {
                    return b.updatedAt.compareTo(a.updatedAt);
                  }
                  if (a.dueAt == null) return 1;
                  if (b.dueAt == null) return -1;
                  return a.dueAt!.compareTo(b.dueAt!);
                });
          listener.add(items);
        } catch (error, stack) {
          listener.addError(error, stack);
        }
      }

      final subscription = _changes.stream.listen((_) => emit());
      listener.onCancel = subscription.cancel;
      emit();
    });
  }

  @override
  Future<String> create(HomeworkItem draft) => _write((items) {
    var sequence = DateTime.now().microsecondsSinceEpoch;
    while (items.any((item) => item.id == 'local-$sequence')) {
      sequence++;
    }
    final id = 'local-$sequence';
    items.add(draft.copyWith(id: id));
    return id;
  });

  Future<int> importSelected(List<HomeworkItem> drafts) => _write((items) {
    final ids = items.map((h) => h.id).toSet();
    final added = drafts.where((h) => ids.add(h.id)).toList();
    items.addAll(added);
    return added.length;
  });

  @override
  Future<void> update(HomeworkItem item) => _write((items) {
    final i = items.indexWhere((h) => h.id == item.id);
    if (i < 0) throw StateError('Läxan finns inte längre.');
    items[i] = item.copyWith(updatedAt: DateTime.now());
  });

  @override
  Future<void> delete(String homeworkId) => _write((items) {
    items.removeWhere((h) => h.id == homeworkId);
  });
}
