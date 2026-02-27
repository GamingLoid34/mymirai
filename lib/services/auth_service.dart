import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_mirai/core/models.dart';

/// Inloggning via e-post/lösenord mot Firestore users.

class AuthService {
  static final _firestore = FirebaseFirestore.instance;
  static const _usersCollection = 'users';

  /// Logga in med e-post och lösenord (mot Firestore users).
  static Future<AppUser?> signIn(String email, String password) async {
    final q = await _firestore
        .collection(_usersCollection)
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;
    final doc = q.docs.first;
    final data = doc.data();
    final storedPassword = data['password']?.toString() ?? '';
    if (storedPassword != password) return null;

    return AppUser.fromMap(doc.id, data);
  }
}
