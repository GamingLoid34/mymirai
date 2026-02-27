import 'package:flutter/material.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';

class NursingProgramPage extends StatelessWidget {
  final AppUser currentUser;

  const NursingProgramPage({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sjuksköterskeprogrammet')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Moduler',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Välj en modul för träning med fokus på säkra beräkningar.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black.withOpacity(0.62),
                  ),
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MedcalcLandingPage(currentUser: currentUser),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: AppTheme.glassCard(context: context),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.calculate_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Läkemedelsberäkning (Säker)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Träna och tentamode med strikt validering',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MedcalcLandingPage extends StatelessWidget {
  final AppUser currentUser;

  const MedcalcLandingPage({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Läkemedelsberäkning (Säker)')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Utbildningsläge: Beräkningar ska verifieras med två metoder innan slutligt facit visas.',
              ),
            ),
            const SizedBox(height: 18),
            _ModeCard(
              title: 'Träna',
              subtitle: 'Stegvis med förklaringar och facit',
              icon: Icons.school_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MedcalcPracticePage(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              title: 'Tentamode',
              subtitle: 'Utan steg-hjälp med poäng och tid',
              icon: Icons.timer_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MedcalcExamPage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: AppTheme.glassCard(context: context),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black.withOpacity(0.62),
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class MedcalcPracticePage extends StatelessWidget {
  const MedcalcPracticePage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ModeScaffold(
      title: 'Träna - Läkemedelsberäkning',
      bullets: const [
        'Stegvis inmatning med enhetstvingade fält',
        'Validering av orimliga värden',
        'Facit + förklaring efter varje svar',
      ],
    );
  }
}

class MedcalcExamPage extends StatelessWidget {
  const MedcalcExamPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ModeScaffold(
      title: 'Tentamode - Läkemedelsberäkning',
      bullets: const [
        'Tidtagning per pass',
        'Inga ledtrådar innan inskickat svar',
        'Resultatöversikt efter avslutad omgång',
      ],
    );
  }
}

class _ModeScaffold extends StatelessWidget {
  final String title;
  final List<String> bullets;

  const _ModeScaffold({
    required this.title,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.glassCard(context: context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MVP-scope',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  ...bullets.map(
                    (bullet) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Icon(Icons.check_circle_rounded, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(bullet)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Nästa steg: koppla in deterministisk beräkningsmotor med dubbelverifiering.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
