import 'package:flutter/material.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';
import 'package:my_mirai/pages/medcalc_page.dart';

class StudyProgramsPage extends StatelessWidget {
  final AppUser currentUser;

  const StudyProgramsPage({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Studieprogram')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient(context)),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Välj program',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Specialiserade spår för gymnasie, universitet och vuxenutbildning.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.mutedText(context),
                  ),
            ),
            const SizedBox(height: 16),
            _ProgramCard(
              title: 'Sjuksköterskeprogrammet',
              subtitle: 'Läkemedelsberäkning med säkerhetsfokus',
              icon: Icons.local_hospital_rounded,
              enabled: currentUser.hasNursingProgram && currentUser.medcalcEnabled,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NursingProgramPage(currentUser: currentUser),
                  ),
                );
              },
            ),
            if (!currentUser.hasNursingProgram) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Programmet är inte aktiverat på profilen ännu. Sätt activePrograms till nursing_rn i user-dokumentet.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  const _ProgramCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.52,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: AppTheme.glassCard(context: context),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.primary),
              ),
              const SizedBox(width: 14),
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
                            color: AppTheme.mutedText(context),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.subtleText(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
