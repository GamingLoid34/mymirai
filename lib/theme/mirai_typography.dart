import 'package:flutter/material.dart';

import 'mirai_tokens.dart';

/// Nunito — rundat, varmt och lättläst (samma som La Familia).
class MiraiTypography {
  MiraiTypography._();

  static TextTheme build() {
    final base = ThemeData.light().textTheme.apply(fontFamily: 'Nunito');
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 40,
        height: 1.1,
        letterSpacing: -1.0,
        fontWeight: FontWeight.w800,
        color: MiraiTokens.textPrimary,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 28,
        height: 1.15,
        letterSpacing: -0.5,
        fontWeight: FontWeight.w800,
        color: MiraiTokens.textPrimary,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 22,
        height: 1.2,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w800,
        color: MiraiTokens.textPrimary,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 18,
        height: 1.3,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w700,
        color: MiraiTokens.textPrimary,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 16,
        height: 1.35,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w700,
        color: MiraiTokens.textPrimary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w700,
        color: MiraiTokens.textPrimary,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: MiraiTokens.textSecondary,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 15,
        height: 1.55,
        fontWeight: FontWeight.w500,
        color: MiraiTokens.textPrimary,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.55,
        fontWeight: FontWeight.w500,
        color: MiraiTokens.textPrimary,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.5,
        fontWeight: FontWeight.w500,
        color: MiraiTokens.textSecondary,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: MiraiTokens.textPrimary,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: MiraiTokens.textSecondary,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: MiraiTokens.textTertiary,
      ),
    );
  }
}
