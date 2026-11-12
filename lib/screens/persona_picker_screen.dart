import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';

class PersonaPickerScreen extends StatefulWidget {
  const PersonaPickerScreen({
    super.key,
    required this.authService,
    required this.onDone,
  });

  final AuthService authService;
  final VoidCallback onDone;

  @override
  State<PersonaPickerScreen> createState() => _PersonaPickerScreenState();
}

class _PersonaPickerScreenState extends State<PersonaPickerScreen> {
  UserPersona _selected = UserPersona.child;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.authService.savePersona(_selected);
      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara visningsläget. Testa igen om en stund.',
        error: e,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Välj visningsläge')),
      body: Center(
        child: MiraiAdaptiveBox(
          child: Padding(
            padding: const EdgeInsets.all(MiraiTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Hur vill du använda My Mirai?', style: tt.titleLarge),
                const SizedBox(height: MiraiTokens.spaceMd),
                _PersonaCard(
                  title: 'För barnen i familjen',
                  subtitle: 'Läxor, sammanfattningar, flashcards och förhör.',
                  selected: _selected == UserPersona.child,
                  onTap: () => setState(() => _selected = UserPersona.child),
                ),
                const SizedBox(height: MiraiTokens.spaceSm),
                _PersonaCard(
                  title: 'För mig själv',
                  subtitle: 'Vuxen-läge för artiklar, dokument och läsning.',
                  selected: _selected == UserPersona.adult,
                  onTap: () => setState(() => _selected = UserPersona.adult),
                ),
                const SizedBox(height: MiraiTokens.spaceSm),
                _PersonaCard(
                  title: 'Båda',
                  subtitle: 'Växla mellan barn- och vuxen-läge i appen.',
                  selected: _selected == UserPersona.both,
                  onTap: () => setState(() => _selected = UserPersona.both),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Fortsätt'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(MiraiTokens.spaceMd),
        decoration: BoxDecoration(
          color: MiraiTokens.bgRaised,
          borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
          border: Border.all(
            color: selected ? MiraiTokens.accent : MiraiTokens.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? MiraiTokens.accent : MiraiTokens.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
