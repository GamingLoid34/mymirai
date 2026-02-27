import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:my_mirai/firebase_options.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/pages/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyMiraiApp());
}

class MyMiraiApp extends StatelessWidget {
  const MyMiraiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Mirai',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const LoginPage(),
    );
  }
}
