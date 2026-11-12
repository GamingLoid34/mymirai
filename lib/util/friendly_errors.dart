import 'package:flutter/material.dart';

/// Visar ett barnvänligt felmeddelande utan tekniska detaljer.
///
/// Den tekniska [error] loggas alltid med `debugPrint` för utvecklare,
/// men visas aldrig för användaren.
void showFriendlySnack(
  BuildContext context,
  String message, {
  VoidCallback? onRetry,
  Object? error,
}) {
  if (error != null) debugPrint('[FriendlyError] $error');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: onRetry == null
          ? null
          : SnackBarAction(label: 'Försök igen', onPressed: onRetry),
    ),
  );
}
