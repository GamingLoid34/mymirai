import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'xp_repository.dart';

/// Firestore-struktur: `user_stats/{uid}` med fälten `xpTotal` (int) och
/// `xpByDay.{yyyy-MM-dd}` (int) — samma dokumentfamilj som lyssningsstatistiken.
class FirestoreXpRepository implements XpRepository {
  FirestoreXpRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String _todayId() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('user_stats').doc(uid);

  @override
  Stream<int> watchXpTotal(String uid) {
    return _userRef(uid).snapshots().map((s) {
      return (s.data()?['xpTotal'] as num?)?.toInt() ?? 0;
    });
  }

  @override
  Stream<Map<String, int>> watchXpByDay(String uid) {
    return _userRef(uid).snapshots().map((s) {
      final raw = s.data()?['xpByDay'];
      if (raw is! Map) return const {};
      final out = <String, int>{};
      for (final entry in raw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is num) out[key] = value.toInt();
      }
      return out;
    });
  }

  @override
  Future<void> addXp(String uid, int amount) async {
    if (amount <= 0) return;
    await _userRef(uid).set(
      {
        'ownerUid': uid,
        'xpTotal': FieldValue.increment(amount),
        'xpByDay.${_todayId()}': FieldValue.increment(amount),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
