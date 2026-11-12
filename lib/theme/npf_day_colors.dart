import 'package:flutter/material.dart';

/// Dagspalett — "varje dag en ädelsten/metall", portad från **La Familia**
/// (`AppTheme.dayPalette`) så att barnen känner igen dagens färg i båda
/// apparna. [light] är glansbandet som ger den metalliska lystern i gradienter.
class DayPalette {
  const DayPalette({
    required this.light,
    required this.base,
    required this.deep,
    required this.onColor,
  });

  final Color light;
  final Color base;
  final Color deep;
  final Color onColor;

  /// Mycket ljus ton av dagsfärgen — för kortbakgrunder (istället för vitt).
  Color get tint => Color.alphaBlend(base.withValues(alpha: 0.07), Colors.white);

  /// Trestegsgradient med glansband upptill: ljus → bas → djup.
  /// Det är detta som ger metall-känslan utan glitter eller reflexer.
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.45, 1.0],
        colors: [light, base, deep],
      );
}

/// NPF-veckodagsfärger med samma juveltoner som **La Familia**.
///
/// [weekday] ska vara som [DateTime.weekday]: **måndag = 1**, **söndag = 7**.
abstract final class NpfDayColors {
  // Mån smaragd · Tis safir · Ons silver · Tor koppar · Fre guld ·
  // Lör roséguld · Sön granat.
  static const Map<int, DayPalette> _palettes = {
    1: DayPalette( // Måndag — smaragd
        light: Color(0xFF6FBF8A),
        base: Color(0xFF4E9D68),
        deep: Color(0xFF2E7D4F),
        onColor: Colors.white),
    2: DayPalette( // Tisdag — safir
        light: Color(0xFF74AEDC),
        base: Color(0xFF4D8FC4),
        deep: Color(0xFF2F6593),
        onColor: Colors.white),
    3: DayPalette( // Onsdag — silver
        light: Color(0xFFB9C3CE),
        base: Color(0xFF8895A3),
        deep: Color(0xFF5C6877),
        onColor: Colors.white),
    4: DayPalette( // Torsdag — koppar
        light: Color(0xFFD08A5A),
        base: Color(0xFFB0683A),
        deep: Color(0xFF7E441F),
        onColor: Colors.white),
    5: DayPalette( // Fredag — guld
        light: Color(0xFFF2CD6B),
        base: Color(0xFFE2B53E),
        deep: Color(0xFFA9802B),
        onColor: Color(0xFF1A1A2E)),
    6: DayPalette( // Lördag — roséguld
        light: Color(0xFFE59CAC),
        base: Color(0xFFD3798F),
        deep: Color(0xFFA94F66),
        onColor: Colors.white),
    7: DayPalette( // Söndag — granat
        light: Color(0xFFD97259),
        base: Color(0xFFC6503E),
        deep: Color(0xFF93331F),
        onColor: Colors.white),
  };

  /// Hela paletten för en veckodag; utan argument → dagens.
  /// Okänt värde → måndag (samma default som La Familia).
  static DayPalette paletteFor([int? weekday]) =>
      _palettes[weekday ?? DateTime.now().weekday] ?? _palettes[1]!;

  /// Dagens basfärg (juvelton).
  static Color forWeekday(int weekday) => paletteFor(weekday).base;

  static String labelSv(int weekday) {
    switch (weekday.clamp(1, 7)) {
      case 1:
        return 'måndag';
      case 2:
        return 'tisdag';
      case 3:
        return 'onsdag';
      case 4:
        return 'torsdag';
      case 5:
        return 'fredag';
      case 6:
        return 'lördag';
      case 7:
        return 'söndag';
      default:
        return 'måndag';
    }
  }
}
