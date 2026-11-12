import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
import 'config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/local_homework_repository.dart';
import 'data/firestore_homework_repository.dart';
import 'data/homework_repository.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'theme/mirai_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: MiraiTokens.bgRaised,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  await MiraiTokens.loadLowStimuli();
  await initializeDateFormatting('sv');

  // VO-01: bakgrundsuppspelning + låsskärmskontroller. Stöds inte på web/Windows.
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.mymirai.my_mirai.channel.audio',
      androidNotificationChannelName: 'My Mirai-uppläsning',
      androidNotificationOngoing: true,
    );
  }
  await NotificationService.instance.init();

  final HomeworkRepository repository;
  final AuthService authService;
  if (kUseFirestoreHomework) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    repository = FirestoreHomeworkRepository();
    authService = AuthService();
    await authService.initialize();
  } else {
    repository = LocalHomeworkRepository(await SharedPreferences.getInstance());
    authService = AuthService.local(uid: kDevAssignedToUserId, familyId: kDevFamilyId);
  }

  runApp(MyMiraiApp(
    homeworkRepository: repository,
    authService: authService,
  ));
}
