import 'package:flutter/material.dart';

import 'mirai_tokens.dart';

/// Visuell färg per ämne; fritext som inte matchar får neutral grå.
Color subjectAccentColor(String subject) {
  final s = subject.trim().toLowerCase();
  if (s.isEmpty || s == 'ämne') return MiraiTokens.textTertiary;

  bool has(String k) => s == k || s.contains(k);

  if (has('matte') || has('matematik')) return MiraiTokens.info;
  if (has('svenska')) return MiraiTokens.success;
  if (has('engelska') || has('spanska') || has('tyska') || has('franska')) {
    return MiraiTokens.accentMuted;
  }
  if (s.trim().toLowerCase() == 'no') return const Color(0xFF2E7D32);
  if (has('biologi')) return const Color(0xFF2E7D32);
  if (has('fysik')) return const Color(0xFF1565C0);
  if (has('kemi')) return const Color(0xFF6A1B9A);
  if (has('historia')) return MiraiTokens.warning;
  if (has('geografi') || has('religion') || has('samhäll')) {
    return const Color(0xFF6D4C41);
  }
  if (s.trim().toLowerCase() == 'so') return const Color(0xFF6D4C41);
  if (has('bild') || has('musik') || has('slöjd')) return MiraiTokens.accent;
  if (has('idrott')) return const Color(0xFFE65100);
  if (has('hemkunskap')) return const Color(0xFFC2185B);
  if (has('teknik')) return const Color(0xFF00838F);
  if (has('modersmål')) return const Color(0xFF5E35B1);

  return MiraiTokens.textTertiary;
}
