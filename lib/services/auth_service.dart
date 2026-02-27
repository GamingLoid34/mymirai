import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:my_mirai/core/models.dart';

/// Inloggning: e-post/lösenord mot Firestore ELLER Google via Firebase Auth.
class AuthService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
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

  /// Logga in med Google (Firebase Auth).
  /// Skapar användare i Firestore om den inte finns.
  static Future<AppUser?> signInWithGoogle() async {
    UserCredential userCred;
    if (kIsWeb) {
      // På webben använder vi Firebase Auth popup-flöde för att undvika
      // OAuth redirect_uri-mismatch med manuellt clientId.
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');
      userCred = await _auth.signInWithPopup(provider);
    } else {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      userCred = await _auth.signInWithCredential(credential);
    }

    final fbUser = userCred.user;
    if (fbUser == null) return null;

    final email = fbUser.email ?? '';
    final name = fbUser.displayName ?? email.split('@').first;
    final uid = fbUser.uid;

    // Finns användaren i Firestore? (sök på email)
    final q = await _firestore
        .collection(_usersCollection)
        .where('email', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) {
      return AppUser.fromMap(q.docs.first.id, q.docs.first.data());
    }

    // Skapa ny användare i Firestore
    final newUser = {
      'name': name,
      'email': email.toLowerCase(),
      'password': '', // Ingen lösenord för Google-användare
      'color': 0xFF4FC3F7,
      'role': UserRole.barn.name,
      'firebaseUid': uid,
    };

    final docRef = await _firestore.collection(_usersCollection).add(newUser);
    return AppUser.fromMap(docRef.id, newUser);
  }
}
