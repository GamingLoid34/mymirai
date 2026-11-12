import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mirai_tokens.dart';
import 'mirai_typography.dart';
import 'npf_day_colors.dart';

/// Ljust La Familia-tema, färgat av dagens juvelton ([NpfDayColors]).
/// I lågstimuli-läge blir bakgrunden neutral och dagsfärgen tonas ner.
ThemeData buildMyMiraiTheme({required DateTime forDate}) {
  final day = NpfDayColors.paletteFor(forDate.weekday);
  final low = MiraiTokens.lowStimuli;
  final textTheme = MiraiTypography.build();

  // Dagens färg syns i "luften" mellan de vita korten, inte i dem.
  final scaffoldBackground = low
      ? const Color(0xFFF4F6F8)
      : Color.alphaBlend(
          day.base.withValues(alpha: 0.10),
          MiraiTokens.bgBase,
        );

  final colorScheme = ColorScheme.light(
    brightness: Brightness.light,
    primary: day.base,
    onPrimary: day.onColor,
    primaryContainer: day.tint,
    onPrimaryContainer: MiraiTokens.textPrimary,
    secondary: MiraiTokens.accent,
    onSecondary: MiraiTokens.textInverse,
    secondaryContainer: MiraiTokens.accentSoft,
    onSecondaryContainer: MiraiTokens.textPrimary,
    tertiary: MiraiTokens.info,
    onTertiary: MiraiTokens.textInverse,
    surface: MiraiTokens.bgRaised,
    onSurface: MiraiTokens.textPrimary,
    surfaceContainerLowest: MiraiTokens.bgRaised,
    surfaceContainerLow: const Color(0xFFFBFAF7),
    surfaceContainer: MiraiTokens.bgBase,
    surfaceContainerHigh: MiraiTokens.bgInteractive,
    surfaceContainerHighest: const Color(0xFFE8E4DB),
    onSurfaceVariant: MiraiTokens.textSecondary,
    outline: MiraiTokens.borderStrong,
    outlineVariant: MiraiTokens.borderSubtle,
    error: MiraiTokens.danger,
    onError: MiraiTokens.textInverse,
    errorContainer: const Color(0xFFF7DEDA),
    onErrorContainer: const Color(0xFF7A2418),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBackground,
      foregroundColor: MiraiTokens.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: const IconThemeData(color: MiraiTokens.textPrimary, size: 22),
    ),
    cardTheme: CardThemeData(
      color: MiraiTokens.bgRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusLg),
        side: BorderSide(
          color: low
              ? Colors.black.withValues(alpha: 0.06)
              : day.base.withValues(alpha: 0.16),
          width: MiraiTokens.borderThin,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: day.base,
        foregroundColor: day.onColor,
        disabledBackgroundColor: MiraiTokens.bgInteractive,
        disabledForegroundColor: MiraiTokens.textTertiary,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: MiraiTokens.spaceLg,
          vertical: MiraiTokens.spaceSm + 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
        ),
        minimumSize: const Size(0, 48),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MiraiTokens.textPrimary,
        side: const BorderSide(
          color: MiraiTokens.borderStrong,
          width: MiraiTokens.borderRegular,
        ),
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: MiraiTokens.spaceLg,
          vertical: MiraiTokens.spaceSm + 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
        ),
        minimumSize: const Size(0, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: day.deep,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: MiraiTokens.spaceMd,
          vertical: MiraiTokens.spaceXs,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MiraiTokens.bgRaised,
      hintStyle: textTheme.bodyMedium?.copyWith(color: MiraiTokens.textTertiary),
      labelStyle: textTheme.labelMedium,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: MiraiTokens.spaceMd,
        vertical: MiraiTokens.spaceSm + 2,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        borderSide: const BorderSide(
          color: MiraiTokens.borderSubtle,
          width: MiraiTokens.borderThin,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        borderSide: const BorderSide(
          color: MiraiTokens.borderSubtle,
          width: MiraiTokens.borderThin,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        borderSide: BorderSide(
          color: day.deep,
          width: MiraiTokens.borderRegular,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        borderSide: const BorderSide(
          color: MiraiTokens.danger,
          width: MiraiTokens.borderRegular,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MiraiTokens.bgRaised,
      side: const BorderSide(
        color: MiraiTokens.borderSubtle,
        width: MiraiTokens.borderThin,
      ),
      labelStyle: textTheme.labelMedium?.copyWith(color: MiraiTokens.textPrimary),
      padding: const EdgeInsets.symmetric(
        horizontal: MiraiTokens.spaceSm,
        vertical: MiraiTokens.space2xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MiraiTokens.bgRaised,
      indicatorColor: low ? MiraiTokens.bgInteractive : day.tint,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return (textTheme.labelMedium ?? const TextStyle()).copyWith(
          color: selected ? MiraiTokens.textPrimary : MiraiTokens.textTertiary,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? day.deep : MiraiTokens.textTertiary,
        );
      }),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: MiraiTokens.bgRaised,
      selectedItemColor: day.deep,
      unselectedItemColor: MiraiTokens.textTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      showSelectedLabels: true,
      showUnselectedLabels: true,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: day.base,
      foregroundColor: day.onColor,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MiraiTokens.textPrimary,
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: MiraiTokens.textInverse),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: MiraiTokens.borderSubtle,
      thickness: MiraiTokens.borderThin,
      space: MiraiTokens.spaceMd,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MiraiTokens.bgElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusLg),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MiraiTokens.bgElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MiraiTokens.radiusXl),
        ),
      ),
    ),
  );
}

/// Header-yta med dagens gradient och rundade nederhörn (som La Familia).
/// I lågstimuli-läge: platt basfärg utan glansband.
BoxDecoration dayHeaderDecoration([int? weekday]) {
  final day = NpfDayColors.paletteFor(weekday);
  return BoxDecoration(
    color: MiraiTokens.lowStimuli ? day.base : null,
    gradient: MiraiTokens.lowStimuli ? null : day.gradient,
    borderRadius: const BorderRadius.vertical(
      bottom: Radius.circular(MiraiTokens.radiusXl),
    ),
  );
}
