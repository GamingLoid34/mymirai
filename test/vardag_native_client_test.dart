import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/data/vardag_letters.dart';

/// Speglar Android-testpaketet innan den första Vardag-importen.
class _EmptyNativeCore extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => [];

  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions options,
  ) async => CoreInitializeResponse(
    name: appName,
    options: options,
    pluginConstants: {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Vardag kan vara den första Firebase-anslutningen på Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestFirebaseCoreHostApi.setUp(_EmptyNativeCore());
    addTearDown(() {
      TestFirebaseCoreHostApi.setUp(null);
      debugDefaultTargetPlatformOverride = null;
    });

    final client = await VardagLetters.openClient();
    expect(client.name, 'vardag-inkorg');
    expect(Firebase.app().name, defaultFirebaseAppName);
    expect(
      FirebaseFirestore.instanceFor(app: client).settings.persistenceEnabled,
      false,
    );
  });
}
