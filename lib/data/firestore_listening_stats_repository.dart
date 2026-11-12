import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Firestore-struktur: `user_stats/{uid}`, subcollection `daily/{yyyy-MM-dd}` (Chunk I).
class FirestoreListeningStatsRepository {
  FirestoreListeningStatsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int defaultDailyGoalSeconds = 1800;

  String _todayId() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  DocumentReference<Map<String, dynamic>> userRef(String uid) =>
      _db.collection('user_stats').doc(uid);

  Stream<int> watchDailyGoalSeconds(String uid) {
    return userRef(uid).snapshots().map((s) {
      final v =
          (s.data()?['dailyGoalSeconds'] as num?)?.toInt() ??
          defaultDailyGoalSeconds;
      return v.clamp(60, 24 * 3600);
    });
  }

  Stream<int> watchListenedSecondsToday(String uid) {
    return userRef(uid).collection('daily').doc(_todayId()).snapshots().map((s) {
      return (s.data()?['listenedSeconds'] as num?)?.toInt() ?? 0;
    });
  }

  Future<void> addListenedSeconds(String uid, int seconds) async {
    if (seconds <= 0) return;
    final uref = userRef(uid);
    final batch = _db.batch();
    batch.set(
      uref,
      {
        'ownerUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      uref.collection('daily').doc(_todayId()),
      {
        'listenedSeconds': FieldValue.increment(seconds),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> setDailyGoalMinutes(String uid, int minutes) async {
    final secs = minutes.clamp(15, 24 * 60) * 60;
    await userRef(uid).set(
      {
        'ownerUid': uid,
        'dailyGoalSeconds': secs,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Hämtar `listenedSeconds` för datum-id:n [ids] parallellt (få dokument per fråga).
  Future<Map<String, int>> fetchListenedSecondsForDayIds(
    String uid,
    Iterable<String> dayIds,
  ) async {
    final out = <String, int>{};
    await Future.wait(
      dayIds.map((id) async {
        final snap = await userRef(uid).collection('daily').doc(id).get();
        final n = (snap.data()?['listenedSeconds'] as num?)?.toInt() ?? 0;
        if (n > 0) out[id] = n;
      }),
    );
    return out;
  }

  /// Senaste [dayCount] dagarna inkl. idag (`yyyy-MM-dd` → sekunder lyssnat).
  Future<Map<String, int>> fetchTrailingDays(String uid, int dayCount) async {
    if (dayCount <= 0) return {};
    final now = DateTime.now();
    final ids = <String>[];
    for (var i = 0; i < dayCount; i++) {
      final d = now.subtract(Duration(days: i));
      ids.add(DateFormat('yyyy-MM-dd').format(d));
    }
    return fetchListenedSecondsForDayIds(uid, ids);
  }
}
