import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Designtokens för my_mirai — **La Familia**-designspråket: ljust, varmt
/// och NPF-vänligt. Dagens juvelfärg kommer från `NpfDayColors` via
/// [buildMyMiraiTheme]; här ligger de neutrala ytorna, texten och skalorna.
class MiraiTokens {
  MiraiTokens._();

  // === Lågstimuli-läge (NPF) ===
  /// Tonar ner dagsfärgad bakgrund, gradienter och skuggor — för dagar då
  /// allt är för mycket. Samma nyckel (`lowStimuli`) som i La Familia.
  static final ValueNotifier<bool> lowStimuliListenable =
      ValueNotifier<bool>(false);
  static bool get lowStimuli => lowStimuliListenable.value;

  static const String _lowStimuliPrefKey = 'lowStimuli';

  static Future<void> loadLowStimuli() async {
    final prefs = await SharedPreferences.getInstance();
    lowStimuliListenable.value = prefs.getBool(_lowStimuliPrefKey) ?? false;
  }

  static Future<void> setLowStimuli(bool value) async {
    lowStimuliListenable.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lowStimuliPrefKey, value);
  }

  // === Färger: yta (varm papperston, vita kort ovanpå) ===
  static const Color bgBase = Color(0xFFF6F6F4);
  static const Color bgRaised = Color(0xFFFFFFFF);
  static const Color bgElevated = Color(0xFFFFFFFF);
  static const Color bgInteractive = Color(0xFFEFECE4);

  // === Färger: text (mörkt bläck på ljus yta) ===
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF54546A);
  static const Color textTertiary = Color(0xFF8A8A99);
  static const Color textInverse = Color(0xFFFFFFFF);

  // === Färger: accent (dämpad lavendel — La Familias medlemsfärg) ===
  static const Color accent = Color(0xFF6B5B95);
  static const Color accentMuted = Color(0xFF55487A);
  static const Color accentSoft = Color(0xFFE9E4F2);

  // === Färger: semantiska (djupa juveltoner, läsbara på ljus yta) ===
  static const Color success = Color(0xFF2E7D4F);
  static const Color warning = Color(0xFFA06B14);
  static const Color danger = Color(0xFFB03A2E);
  static const Color info = Color(0xFF2F6593);

  // === Färger: gränser ===
  static const Color borderSubtle = Color(0xFFE6E2D9);
  static const Color borderStrong = Color(0xFFC9C4BA);

  // === Spacing-skala ===
  static const double space2xs = 4;
  static const double spaceXs = 8;
  static const double spaceSm = 12;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double space2xl = 48;

  // === Radius-skala ===
  static const double radiusSm = 8;
  static const double radiusMd = 14;
  static const double radiusLg = 24;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  // === Border widths ===
  static const double borderThin = 1;
  static const double borderRegular = 1;

  // === Animation durations ===
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);

  // === Elevation (mjuka skuggor; inga alls i lågstimuli-läge) ===
  static List<BoxShadow> get shadowSm => lowStimuli
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  static List<BoxShadow> get shadowMd => lowStimuli
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ];

  static List<BoxShadow> get shadowLg => lowStimuli
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ];
}
