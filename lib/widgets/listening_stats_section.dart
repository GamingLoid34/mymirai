import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/document_repository.dart';
import '../data/firestore_listening_stats_repository.dart';
import '../models/document.dart';
import '../theme/mirai_tokens.dart';

/// Veckodiagram + summering (Chunk I, vuxen Mer-flik).
class ListeningStatsSection extends StatelessWidget {
  const ListeningStatsSection({
    super.key,
    required this.uid,
    required this.stats,
    required this.documentRepository,
  });

  final String uid;
  final FirestoreListeningStatsRepository stats;
  final DocumentRepository documentRepository;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Lyssningsstatistik', style: tt.titleMedium),
        const SizedBox(height: MiraiTokens.spaceSm),
        FutureBuilder<Map<String, int>>(
          future: stats.fetchTrailingDays(uid, 60),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(MiraiTokens.spaceLg),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final data = snap.data!;
            final sum60 = data.values.fold<int>(0, (a, b) => a + b);
            final h60 = sum60 ~/ 3600;
            final m60 = (sum60 % 3600) ~/ 60;

            final now = DateTime.now();
            final orderedWeekIds = List<String>.generate(
              7,
              (i) => DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: 6 - i))),
            );
            final weekValues = [for (final id in orderedWeekIds) data[id] ?? 0];
            final maxS = weekValues.fold<int>(0, (a, b) => a > b ? a : b);
            const barH = 96.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: barH + 28,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  height: maxS <= 0
                                      ? 2.0
                                      : (weekValues[i] / maxS * barH).clamp(3.0, barH),
                                  decoration: BoxDecoration(
                                    color: MiraiTokens.accent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${DateTime.parse(orderedWeekIds[i]).day}/${DateTime.parse(orderedWeekIds[i]).month}',
                                  style: tt.labelSmall?.copyWith(
                                    color: MiraiTokens.textTertiary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: MiraiTokens.spaceMd),
                Text(
                  'Senaste 60 dagar: ${h60}h ${m60}m spelad uppläsning (uppskattat).',
                  style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: MiraiTokens.spaceLg),
        Text('Bibliotek', style: tt.titleMedium),
        const SizedBox(height: MiraiTokens.spaceSm),
        StreamBuilder<List<UserDocument>>(
          stream: documentRepository.watchForOwner(uid),
          builder: (context, docSnap) {
            final n = docSnap.data?.length ?? 0;
            return Text(
              '$n sparade dokument',
              style: tt.bodyMedium?.copyWith(color: MiraiTokens.textSecondary),
            );
          },
        ),
        const SizedBox(height: MiraiTokens.spaceSm),
        Text(
          'Kort repeterade (SM‑2) visas i barnläget; vuxen-statistik för kort kommer senare.',
          style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
        ),
      ],
    );
  }
}
