/// Standardläget sparar läxor på enheten. Vardags inkorg ansluts separat.
/// Set to true (or pass --dart-define=USE_FIRESTORE_HOMEWORK=true) when
/// `flutterfire configure` is done and Firestore rules + `users/{uid}.familyId` exist.
const bool kUseFirestoreHomework = bool.fromEnvironment(
  'USE_FIRESTORE_HOMEWORK',
  defaultValue: false,
);

/// Development family id fallback (test/dev only).
/// Runtime uses `users/{uid}.familyId` from Firebase Auth + Firestore.
const String kDevFamilyId = String.fromEnvironment(
  'FAMILY_ID',
  defaultValue: 'demo-family',
);

/// Development assigned user fallback (test/dev only).
/// Runtime currently sets `assignedToUserId = auth.uid`.
const String kDevAssignedToUserId = String.fromEnvironment(
  'CHILD_USER_ID',
  defaultValue: 'demo-child',
);
