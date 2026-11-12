import 'package:flutter/material.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/homework_repository.dart';
import 'screens/auth_gate_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'theme/mirai_tokens.dart';

class MyMiraiApp extends StatefulWidget {
  const MyMiraiApp({
    super.key,
    required this.homeworkRepository,
    required this.authService,
  });

  final HomeworkRepository homeworkRepository;
  final AuthService authService;

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  State<MyMiraiApp> createState() => _MyMiraiAppState();
}

class _MyMiraiAppState extends State<MyMiraiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MiraiTokens.lowStimuliListenable,
      builder: (context, _, child) => MaterialApp(
        title: 'My Mirai',
        locale: const Locale('sv'),
        supportedLocales: const [Locale('sv'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        scaffoldMessengerKey: MyMiraiApp.scaffoldMessengerKey,
        theme: buildMyMiraiTheme(forDate: DateTime.now()),
        home: AuthGateScreen(
          authService: widget.authService,
          homeworkRepository: widget.homeworkRepository,
        ),
      ),
    );
  }
}
