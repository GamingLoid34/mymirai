import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central tema för My Mirai.
/// Mjuk "edtech"-känsla i lila toner.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF6C63FF);
  static const Color secondary = Color(0xFFA79CFF);
  static const Color accent = Color(0xFFDCD5FF);
  static const Color background = Color(0xFFF5F4FF);
  static const Color textStrong = Color(0xFF26223C);

  /// Dyslexivänligt typsnitt.
  static String get dyslexiFontFamily => 'Lexend';

  static Color get dayColor => primary;

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      secondary: secondary,
      surface: Colors.white,
      onSurface: textStrong,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: GoogleFonts.lexendTextTheme(
        ThemeData.light().textTheme,
      ).apply(
        bodyColor: textStrong,
        displayColor: textStrong,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textStrong,
        titleTextStyle: GoogleFonts.lexend(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: textStrong,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.lexend(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textStrong,
          side: BorderSide(color: Colors.black.withOpacity(0.08)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.white.withOpacity(0.95),
        indicatorColor: primary.withOpacity(0.14),
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.lexend(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.lexendTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.lexend(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF201B35),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        color: const Color(0xFF201B35),
      ),
    );
  }

  static LinearGradient get pageGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE7E1FF),
      Color(0xFFF6F3FF),
      Color(0xFFFFFFFF),
    ],
  );

  static LinearGradient get primaryGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C73FF),
      Color(0xFF9E93FF),
    ],
  );

  /// Mjukt "glass card"-utseende.
  static BoxDecoration glassCard({
    required BuildContext context,
    double opacity = 0.9,
    double blur = 14,
    double radius = 22,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: (isDark ? const Color(0xFF201B35) : Colors.white).withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: primary.withOpacity(isDark ? 0.15 : 0.12),
          blurRadius: blur,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
