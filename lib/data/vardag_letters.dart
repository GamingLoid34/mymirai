import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../services/school_letter.dart';

/// Läser SchoolSoft-poster via Vardags egna familje- och synlighetsvillkor.
/// Inloggningen lever bara medan breven hämtas. Bara valda uppgifter sparas.
class VardagLetters {
  static Future<FirebaseApp>? _client;
  static const _emulator = bool.fromEnvironment('MIRAI_TEST_VARDAG_EMULATOR');

  @visibleForTesting
  static Future<FirebaseApp> openClient() async {
    final options = _emulator
        ? const FirebaseOptions(
            apiKey: 'demo-mirai',
            appId: '1:123456789:web:123456789',
            messagingSenderId: '123456789',
            projectId: 'demo-mirai',
          )
        : DefaultFirebaseOptions.currentPlatform;
    if (!_emulator && options.projectId != 'la-familia-5d9f5') {
      throw StateError('Vardags klientkonfiguration saknas.');
    }
    final app = await Firebase.initializeApp(
      name: 'vardag-inkorg',
      options: options,
    );
    // FlutterFires native Firestore-delegat slår upp standardappen även för
    // instanceFor. Ett fristående testpaket har ingen automatiskt skapad sådan.
    if (!kIsWeb &&
        !Firebase.apps.any((a) => a.name == defaultFirebaseAppName)) {
      await Firebase.initializeApp(options: options);
    }
    final db = FirebaseFirestore.instanceFor(app: app);
    db.settings = const Settings(persistenceEnabled: false);
    final auth = FirebaseAuth.instanceFor(app: app);
    if (_emulator) {
      await auth.useAuthEmulator('localhost', 9134);
      db.useFirestoreEmulator('localhost', 8134);
    }
    if (kIsWeb) await auth.setPersistence(Persistence.NONE);
    return app;
  }

  static Future<List<SchoolLetter>> fetch(String email, String password) async {
    late final FirebaseApp app;
    try {
      app = await (_client ??= openClient());
    } catch (_) {
      _client = null;
      rethrow;
    }
    final auth = FirebaseAuth.instanceFor(app: app);
    final db = FirebaseFirestore.instanceFor(app: app);
    const server = GetOptions(source: Source.server);
    try {
      final login = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = login.user!.uid;
      final profile = (await db.collection('users').doc(uid).get(server))
          .data();
      final familyId = profile?['familyId'];
      if (familyId is! String || familyId.isEmpty) {
        throw StateError('Kontot saknar familj i Vardag.');
      }
      if (!['parent', 'admin'].contains(profile?['role'])) {
        throw StateError('Vardags inkorg kräver ett vuxenkonto.');
      }
      final notes = db
          .collection('notes')
          .where('familyId', isEqualTo: familyId)
          .where('source', isEqualTo: 'rss');
      final groups = await Future.wait([
        notes.where('visibility', isEqualTo: 'family').get(server),
        notes.where('ownerUid', isEqualTo: uid).get(server),
      ]);
      final letters = <String, SchoolLetter>{};
      for (final group in groups) {
        for (final note in group.docs) {
          final data = note.data();
          final body = data['text'];
          if (data['deletedAt'] != null ||
              body is! String ||
              body.trim().isEmpty) {
            continue;
          }
          final date = data['publishedAt'] ?? data['createdAt'];
          final title = (data['title'] as String?)?.trim();
          letters[note.id] = SchoolLetter(
            noteId: note.id,
            title: title == null || title.isEmpty
                ? 'Skolnyhet från Vardag'
                : title,
            text: body,
            publishedAt: date is Timestamp ? date.toDate() : null,
            fromVardag: true,
          );
        }
      }
      return letters.values.toList()..sort(
        (a, b) => (b.publishedAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.publishedAt?.millisecondsSinceEpoch ?? 0,
        ),
      );
    } finally {
      await auth.signOut();
    }
  }
}
