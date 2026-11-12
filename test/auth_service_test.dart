import 'package:flutter_test/flutter_test.dart';

import 'package:my_mirai/services/auth_service.dart';

void main() {
  test('testSignedIn exposes session uid and familyId', () {
    final svc = AuthService.testSignedIn(
      uid: 'user-99',
      familyId: 'family-abc',
      displayName: 'Test',
    );
    expect(svc.status, AuthStatus.signedIn);
    expect(svc.session?.uid, 'user-99');
    expect(svc.session?.familyId, 'family-abc');
    expect(svc.needsPersonaOnboarding, isFalse);
  });

  test('both persona: active starts as child and can toggle', () {
    final svc = AuthService.testSignedIn(
      uid: 'u',
      familyId: 'f',
      savedPersona: UserPersona.both,
    );
    expect(svc.savedPersona, UserPersona.both);
    expect(svc.activePersona, UserPersona.child);
    svc.setActivePersona(UserPersona.adult);
    expect(svc.activePersona, UserPersona.adult);
    expect(svc.savedPersona, UserPersona.both);
  });

  test('non-both persona: setActivePersona is ignored', () {
    final child = AuthService.testSignedIn(
      uid: 'u',
      familyId: 'f',
      savedPersona: UserPersona.child,
    );
    child.setActivePersona(UserPersona.adult);
    expect(child.activePersona, UserPersona.child);

    final adult = AuthService.testSignedIn(
      uid: 'u',
      familyId: 'f',
      savedPersona: UserPersona.adult,
    );
    adult.setActivePersona(UserPersona.child);
    expect(adult.activePersona, UserPersona.adult);
  });

  test('needsPersonaOnboarding flag', () {
    final svc = AuthService.testSignedIn(
      uid: 'u',
      familyId: 'f',
      needsPersonaOnboarding: true,
    );
    expect(svc.needsPersonaOnboarding, isTrue);
  });

  test('test mode signOut clears session', () async {
    final svc = AuthService.testSignedIn(uid: 'u', familyId: 'f');
    await svc.signOut();
    expect(svc.status, AuthStatus.signedOut);
    expect(svc.session, isNull);
    expect(svc.needsPersonaOnboarding, isFalse);
  });
}
