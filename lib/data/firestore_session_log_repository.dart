import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/study_session_log.dart';
import 'session_log_repository.dart';

class FirestoreSessionLogRepository implements SessionLogRepository {
  FirestoreSessionLogRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection('session_logs');

  @override
  Future<void> saveLog(StudySessionLog log) async {
    final docRef = log.id.isNotEmpty
        ? _collection.doc(log.id)
        : _collection.doc();
    await docRef.set(log.toFirestore());
  }

  @override
  Stream<List<StudySessionLog>> watchLogsForHomework(String homeworkId) {
    return _collection
        .where('homeworkId', isEqualTo: homeworkId)
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(StudySessionLog.fromFirestore).toList());
  }

  @override
  Future<StudySessionLog?> getLatestLogForHomework(String homeworkId) async {
    final snap = await _collection
        .where('homeworkId', isEqualTo: homeworkId)
        .orderBy('completedAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return StudySessionLog.fromFirestore(snap.docs.first);
  }
}
