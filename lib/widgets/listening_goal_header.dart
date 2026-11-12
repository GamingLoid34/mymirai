import 'package:flutter/material.dart';

import '../data/firestore_listening_stats_repository.dart';
import '../theme/mirai_tokens.dart';
import '../util/listening_streak.dart';

/// Daglig mål-cirkel + streak-chip (Chunk I, vuxen Hem).
class ListeningGoalHeader extends StatelessWidget {
  const ListeningGoalHeader({
    super.key,
    required this.uid,
    required this.stats,
  });

  final String uid;
  final FirestoreListeningStatsRepository stats;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: stats.watchDailyGoalSeconds(uid),
      builder: (context, goalSnap) {
        final goal = goalSnap.data ?? FirestoreListeningStatsRepository.defaultDailyGoalSeconds;
        return StreamBuilder<int>(
          stream: stats.watchListenedSecondsToday(uid),
          builder: (context, listenedSnap) {
            final listened = listenedSnap.data ?? 0;
            final ratio = goal > 0 ? (listened / goal).clamp(0.0, 1.0) : 0.0;
            final listenedMin = (listened / 60).floor();
            final goalMin = (goal / 60).round();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () =>
                            showModalBottomSheet<void>(
                              context: context,
                              backgroundColor: MiraiTokens.bgElevated,
                              builder: (ctx) => _GoalPickSheet(
                                stats: stats,
                                uid: uid,
                                goalMinutesCur: goalMin,
                              ),
                            ),
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CircularProgressIndicator(
                                value: ratio,
                                strokeWidth: 10,
                                backgroundColor: MiraiTokens.borderSubtle,
                                color: MiraiTokens.accent,
                              ),
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$listenedMin min',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      'av $goalMin min mål',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: MiraiTokens.textTertiary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: MiraiTokens.spaceMd),
                    KeyedSubtree(
                      key: ValueKey<int>(goal),
                      child: _StreakBadge(uid: uid, stats: stats, goalSeconds: goal),
                    ),
                  ],
                ),
                const SizedBox(height: MiraiTokens.spaceSm),
                Text(
                  'Tap på cirkeln för att ändra daglig måltid för uppläsning.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: MiraiTokens.textTertiary,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _GoalPickSheet extends StatelessWidget {
  const _GoalPickSheet({
    required this.stats,
    required this.uid,
    required this.goalMinutesCur,
  });

  final FirestoreListeningStatsRepository stats;
  final String uid;
  final int goalMinutesCur;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    const opts = [15, 30, 60, 90];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(MiraiTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Dagligt lyssningsmål', style: tt.titleMedium),
            const SizedBox(height: MiraiTokens.spaceSm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in opts)
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: m == goalMinutesCur,
                    onSelected: (_) async {
                      await stats.setDailyGoalMinutes(uid, m);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stäng')),
          ],
        ),
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({
    required this.uid,
    required this.stats,
    required this.goalSeconds,
  });

  final String uid;
  final FirestoreListeningStatsRepository stats;
  final int goalSeconds;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: stats.fetchTrailingDays(uid, 45),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 32,
            width: 88,
            child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final streak = computeListeningStreakDays(
          todayLocal: DateTime.now(),
          dailyGoalSeconds: goalSeconds,
          listenedByYyyyMmDd: snap.data!,
        );
        final label =
            streak == 0 ? 'Ingen serie än' : (streak == 1 ? '1 dag serie' : '$streak dagar serie');

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MiraiTokens.spaceMd,
            vertical: MiraiTokens.spaceXs,
          ),
          decoration: BoxDecoration(
            color: MiraiTokens.bgRaised,
            borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
            border: Border.all(color: MiraiTokens.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_rounded, size: 18, color: MiraiTokens.accent),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              Text(
                'Målstreck per dag',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: MiraiTokens.textTertiary,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
