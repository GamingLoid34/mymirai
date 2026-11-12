import 'package:flutter/material.dart';

class MissingFamilyScreen extends StatelessWidget {
  const MissingFamilyScreen({
    super.key,
    required this.onSignOut,
    required this.onRetry,
  });

  final Future<void> Function() onSignOut;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.family_restroom_outlined,
                size: 56,
                color: cs.primary,
              ),
              const SizedBox(height: 14),
              Text(
                'Familj saknas',
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Det här Google-kontot finns inte i någon familj än. '
                'Öppna La Familia-appen, skapa eller gå med i en familj, och kom sedan tillbaka hit.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: onSignOut,
                    child: const Text('Logga ut'),
                  ),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Försök igen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
