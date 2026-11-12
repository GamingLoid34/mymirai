import 'package:flutter/material.dart';

import '../config.dart';
import '../data/deck_repository.dart';
import '../data/dev_document_repository.dart';
import '../data/dev_xp_repository.dart';
import '../data/document_repository.dart';
import '../data/firestore_document_repository.dart';
import '../data/firestore_deck_repository.dart';
import '../data/firestore_listening_stats_repository.dart';
import '../data/firestore_xp_repository.dart';
import '../data/homework_repository.dart';
import '../data/xp_repository.dart';
import '../services/auth_service.dart';
import 'missing_family_screen.dart';
import 'persona_picker_screen.dart';
import 'shell_screen.dart';
import 'sign_in_screen.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({
    super.key,
    required this.authService,
    required this.homeworkRepository,
  });

  final AuthService authService;
  final HomeworkRepository homeworkRepository;

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  String? _cachedDeckFamilyId;
  FirestoreDeckRepository? _cachedFirestoreDeck;
  final XpRepository _xpRepository =
      kUseFirestoreHomework ? FirestoreXpRepository() : DevXpRepository();

  HomeworkRepository get _homeworkRepository => widget.homeworkRepository;

  AuthService get _authService => widget.authService;

  DeckRepository? _deckRepositoryForFirestoreSession(AuthSession session) {
    if (!kUseFirestoreHomework) {
      _clearFirestoreDeckCache();
      return null;
    }
    if (_cachedDeckFamilyId != session.familyId) {
      _cachedDeckFamilyId = session.familyId;
      _cachedFirestoreDeck = FirestoreDeckRepository(familyId: session.familyId);
    }
    return _cachedFirestoreDeck;
  }

  void _clearFirestoreDeckCache() {
    _cachedDeckFamilyId = null;
    _cachedFirestoreDeck = null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _authService,
      builder: (context, _) {
        switch (_authService.status) {
          case AuthStatus.unknown:
            _clearFirestoreDeckCache();
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Loggar in…'),
                  ],
                ),
              ),
            );
          case AuthStatus.signedOut:
            _clearFirestoreDeckCache();
            return SignInScreen(
              errorMessage: _authService.errorMessage,
              onSignIn: _authService.signInWithEmail,
            );
          case AuthStatus.missingFamily:
            _clearFirestoreDeckCache();
            return MissingFamilyScreen(
              onSignOut: _authService.signOut,
              onRetry: _authService.initialize,
            );
          case AuthStatus.signedIn:
            final session = _authService.session;
            if (session == null) {
              _clearFirestoreDeckCache();
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final DocumentRepository documentRepository = kUseFirestoreHomework
                ? FirestoreDocumentRepository()
                : DevDocumentRepository();
            if (_authService.needsPersonaOnboarding) {
              _clearFirestoreDeckCache();
              return PersonaPickerScreen(
                authService: _authService,
                onDone: _authService.initialize,
              );
            }
            final DeckRepository? deckRepository =
                _deckRepositoryForFirestoreSession(session);
            final listeningStatsRepo =
                kUseFirestoreHomework ? FirestoreListeningStatsRepository() : null;
            return ShellScreen(
              homeworkRepository: _homeworkRepository,
              deckRepository: deckRepository,
              documentRepository: documentRepository,
              listeningStatsRepository: listeningStatsRepo,
              xpRepository: _xpRepository,
              familyId: session.familyId,
              assignedToUserId: session.uid,
              authService: _authService,
            );
        }
      },
    );
  }
}
