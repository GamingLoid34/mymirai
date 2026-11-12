import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/homework_item.dart';
import 'homework_repository.dart';

class FirestoreHomeworkRepository implements HomeworkRepository {
  FirestoreHomeworkRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('homework');

  @override
  Stream<List<HomeworkItem>> watchForFamily({
    required String familyId,
    String? assignedToUserId,
  }) {
    // Single-field query avoids composite indexes; filter child in memory.
    final q = _col.where('familyId', isEqualTo: familyId);
    return q.snapshots().map((snap) {
      var list = snap.docs.map(HomeworkItem.fromFirestore).toList();
      if (assignedToUserId != null && assignedToUserId.isNotEmpty) {
        list = list
            .where((h) => h.assignedToUserId == assignedToUserId)
            .toList();
      }
      list.sort((a, b) {
        if (a.dueAt == null && b.dueAt == null) {
          return b.updatedAt.compareTo(a.updatedAt);
        }
        if (a.dueAt == null) return 1;
        if (b.dueAt == null) return -1;
        return a.dueAt!.compareTo(b.dueAt!);
      });
      return list;
    });
  }

  @override
  Future<String> create(HomeworkItem draft) async {
    final now = DateTime.now();
    final ref = await _col.add(draft.toFirestoreCreate(now: now));
    return ref.id;
  }

  @override
  Future<void> update(HomeworkItem item) async {
    final now = DateTime.now();
    await _col.doc(item.id).update(item.toFirestoreUpdate(now: now));
  }

  @override
  Future<void> delete(String homeworkId) async {
    await _col.doc(homeworkId).delete();
  }
}
