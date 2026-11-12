import 'package:flutter/material.dart';

/// Färgnamn för [DocumentHighlight.color] — sparas som sträng i Firestore.
abstract final class HighlightPalette {
  HighlightPalette._();

  static const List<String> ids = [
    'yellow',
    'green',
    'blue',
    'pink',
    'orange',
  ];

  static const yellow = Color(0xFFFFE066);
  static const green = Color(0xFF95D5B2);
  static const blue = Color(0xFFA5C9FF);
  static const pink = Color(0xFFFFC2D7);
  static const orange = Color(0xFFFFB084);

  static Color resolve(String colorKey) {
    switch (colorKey.toLowerCase()) {
      case 'yellow':
        return yellow;
      case 'green':
        return green;
      case 'blue':
        return blue;
      case 'pink':
        return pink;
      case 'orange':
        return orange;
      default:
        return yellow;
    }
  }
}
