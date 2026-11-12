import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum AuthStatus { unknown, signedOut, signedIn, missingFamily }
enum UserPersona { child, adult, both }

UserPersona _parsePersona(String? raw) {
  switch (raw) {
    case 'adult':
      return UserPersona.adult;
    case 'both':
      return UserPersona.both;
    case 'child':
    default:
      return UserPersona.child;
  }
}

String _personaWire(UserPersona p) {
  switch (p) {
    case UserPersona.adult:
      return 'adult';
    case UserPersona.both:
      return 'both';
    case UserPersona.child:
      return 'child';
  }
}

class AuthSession {
  const AuthSession({
    required this.uid,
    required this.familyId,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String familyId;
  final String? displayName;
  final String? photoUrl;
}

class AuthService extends ChangeNotifier {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  AuthService.testSignedIn({
    required String uid,
    required String familyId,
    String? displayName,
    String? photoUrl,
    UserPersona savedPersona = UserPersona.child,
    bool needsPersonaOnboarding = false,
  }) : this.local(uid: uid, familyId: familyId, displayName: displayName,
          photoUrl: photoUrl, savedPersona: savedPersona,
          needsPersonaOnboarding: needsPersonaOnboarding);

  AuthService.local({
    required String uid,
    required String familyId,
    String? displayName,
    String? photoUrl,
    UserPersona savedPersona = UserPersona.child,
    bool needsPersonaOnboarding = false,
  })  : _auth = null,
        _firestore = null {
    _status = AuthStatus.signedIn;
    _session = AuthSession(
      uid: uid,
      familyId: familyId,
      displayName: displayName,
      photoUrl: photoUrl,
    );
    _savedPersona = savedPersona;
    _activePersona =
        savedPersona == UserPersona.both ? UserPersona.child : savedPersona;
    _needsPersonaOnboarding = needsPersonaOnboarding;
    _isLocalSession = true;
  }

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;

  bool _isLocalSession = false;
  bool _initialized = false;
  StreamSubscription<User?>? _sub;

  AuthStatus _status = AuthStatus.unknown;
  AuthSession? _session;
  String? _errorMessage;
  UserPersona _savedPersona = UserPersona.child;
  UserPersona _activePersona = UserPersona.child;
  bool _needsPersonaOnboarding = false;

  AuthStatus get status => _status;
  AuthSession? get session => _session;
  String? get errorMessage => _errorMessage;
  UserPersona get savedPersona => _savedPersona;
  UserPersona get activePersona => _activePersona;
  bool get needsPersonaOnboarding => _needsPersonaOnboarding;

  Future<void> initialize() async {
    if (_isLocalSession) return;
    if (_initialized) {
      await _resolveCurrentUser(_auth?.currentUser);
      return;
    }
    _initialized = true;
    final auth = _auth;
    if (auth == null) return;
    _sub = auth.authStateChanges().listen(
      (user) {
        _resolveCurrentUser(user);
      },
      onError: (_) {
        _status = AuthStatus.signedOut;
        _session = null;
        _errorMessage = 'Kunde inte läsa inloggningsstatus. Försök igen.';
        notifyListeners();
      },
    );
    await _resolveCurrentUser(auth.currentUser);
  }

  Future<void> _resolveCurrentUser(User? user) async {
    _errorMessage = null;
    if (user == null) {
      debugPrint('[auth] signed out');
      _status = AuthStatus.signedOut;
      _session = null;
      _needsPersonaOnboarding = false;
      notifyListeners();
      return;
    }

    try {
      debugPrint('[auth] resolving session from users/{uid}');
      final firestore = _firestore;
      if (firestore == null) {
        _status = AuthStatus.signedOut;
        _session = null;
        _errorMessage = 'Kunde inte hämta användarens familjekoppling.';
        notifyListeners();
        return;
      }
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        _status = AuthStatus.missingFamily;
        _session = null;
        _errorMessage =
            'Den här användaren saknar koppling till en familj. Logga in i La Familia först och sätt upp familjen där.';
        debugPrint('[auth] users/{uid} saknas');
        notifyListeners();
        return;
      }
      final familyId = userDoc.data()?['familyId'] as String?;
      final personaRaw = userDoc.data()?['persona'] as String?;
      _savedPersona = _parsePersona(personaRaw);
      _activePersona =
          _savedPersona == UserPersona.both ? UserPersona.child : _savedPersona;
      _needsPersonaOnboarding = personaRaw == null || personaRaw.trim().isEmpty;
      if (familyId == null || familyId.trim().isEmpty) {
        _status = AuthStatus.missingFamily;
        _session = null;
        _errorMessage =
            'Den här användaren saknar koppling till en familj. Logga in i La Familia först och sätt upp familjen där.';
        debugPrint('[auth] missing familyId');
      } else {
        _status = AuthStatus.signedIn;
        _session = AuthSession(
          uid: user.uid,
          familyId: familyId.trim(),
          displayName: user.displayName,
          photoUrl: user.photoURL,
        );
        debugPrint('[auth] signed in with family');
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _status = AuthStatus.missingFamily;
        _session = null;
        _errorMessage =
            'Saknar behörighet — har du gått med i en familj i La Familia?';
        debugPrint('[auth] permission denied on users/{uid}');
      } else {
        _status = AuthStatus.signedOut;
        _session = null;
        _needsPersonaOnboarding = false;
        if (kDebugMode) {
          _errorMessage = 'Kunde inte hämta användarens familjekoppling (${e.code}).';
        } else {
          _errorMessage = 'Kunde inte hämta användarens familjekoppling.';
        }
        debugPrint('[auth] firebase error while reading users/{uid}: ${e.code}');
      }
    } catch (e) {
      _status = AuthStatus.signedOut;
      _session = null;
      _needsPersonaOnboarding = false;
      _errorMessage = 'Kunde inte hämta användarens familjekoppling.';
      debugPrint('[auth] unexpected error while reading users/{uid}: $e');
    }
    notifyListeners();
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (_isLocalSession) return;
    _errorMessage = null;
    notifyListeners();
    try {
      final auth = _auth;
      if (auth == null) return;
      await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          _errorMessage = 'Fel e-post eller lösenord';
          break;
        case 'invalid-email':
          _errorMessage = 'Ogiltig e-postadress';
          break;
        case 'user-disabled':
          _errorMessage = 'Kontot är inaktiverat';
          break;
        case 'too-many-requests':
          _errorMessage = 'För många försök. Vänta en stund och prova igen.';
          break;
        case 'network-request-failed':
          _errorMessage = 'Ingen internetanslutning';
          break;
        default:
          _errorMessage = 'Något gick fel. Prova igen.';
      }
      notifyListeners();
    } catch (_) {
      _errorMessage = 'Något gick fel. Prova igen.';
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (_isLocalSession) {
      _status = AuthStatus.signedOut;
      _session = null;
      _needsPersonaOnboarding = false;
      notifyListeners();
      return;
    }
    await _auth?.signOut();
  }

  void setActivePersona(UserPersona persona) {
    if (_savedPersona != UserPersona.both) return;
    if (_activePersona == persona) return;
    _activePersona = persona;
    notifyListeners();
  }

  Future<void> savePersona(UserPersona persona) async {
    final uid = _auth?.currentUser?.uid;
    final firestore = _firestore;
    if (uid == null || firestore == null) return;
    await firestore.collection('users').doc(uid).set(
      {'persona': _personaWire(persona)},
      SetOptions(merge: true),
    );
    _savedPersona = persona;
    _activePersona = persona == UserPersona.both ? UserPersona.child : persona;
    _needsPersonaOnboarding = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
