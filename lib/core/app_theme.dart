import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central tema för My Mirai.
/// Glassmorphism, dynamiska dagfärger och dyslexi-font.
class AppTheme {
  AppTheme._();

  /// Dyslexivänlig typsnitt (OpenDyslexic eller Lexend).
  static String get dyslexiFontFamily => 'Lexend';

  /// Hämta dagens basfärg baserat på tid på dygnet.
  static Color get dayColor {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) return const Color(0xFF4FC3F7);  // Morgon – ljusblå
    if (hour >= 12 && hour < 18) return const Color(0xFF66BB6A); // Eftermiddag – grön
    if (hour >= 18 && hour < 22) return const Color(0xFFFFB74D);  // Kväll – apelsin
    return const Color(0xFF7E57C2);  // Natt – lila
  }

  static ThemeData get lightTheme {
    final base = dayColor;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: base,
        brightness: Brightness.light,
        primary: base,
      ),
      textTheme: GoogleFonts.lexendTextTheme(
        ThemeData.light().textTheme,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.lexend(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white.withOpacity(0.7),
      ),
    );
  }

  static ThemeData get darkTheme {
    final base = dayColor;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: base,
        brightness: Brightness.dark,
        primary: base,
      ),
      textTheme: GoogleFonts.lexendTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.lexend(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.grey[900]!.withOpacity(0.7),
      ),
    );
  }

  /// Glassmorphism-boxdekoration.
  static BoxDecoration glassCard({
    required BuildContext context,
    double opacity = 0.25,
    double blur = 10,
    double radius = 16,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: (isDark ? (Colors.grey[900] ?? Colors.black) : Colors.white).withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
          blurRadius: blur,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
