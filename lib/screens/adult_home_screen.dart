import 'package:flutter/material.dart';

import '../config.dart';
import '../data/document_repository.dart';
import '../data/firestore_listening_stats_repository.dart';
import '../models/document.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../services/listening_queue.dart';
import '../util/continue_listening.dart';
import '../util/document_labels.dart';
import '../widgets/audio_player_sheet.dart';
import '../widgets/document_add_menu.dart';
import '../widgets/listening_goal_header.dart';
import '../widgets/listening_queue_sheet.dart';
import 'document_detail_screen.dart';

class AdultHomeScreen extends StatelessWidget {
  const AdultHomeScreen({
    super.key,
    required this.repository,
    required this.ownerUid,
    this.authService,
    this.listeningStats,
  });

  final DocumentRepository repository;
  final String ownerUid;
  /// När persona är **both** visas växling till barnläget (samma källa som Hem i shell).
  final AuthService? authService;
  final FirestoreListeningStatsRepository? listeningStats;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return StreamBuilder<List<UserDocument>>(
      stream: repository.watchForOwner(ownerUid),
      builder: (context, snap) {
        final docs = snap.data ?? const <UserDocument>[];
        final a = authService;
        final showPersonaSwitcher =
            a != null && a.savedPersona == UserPersona.both;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: MiraiAdaptiveBox(
                child: ListView(
                  padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                  children: [
                    if (showPersonaSwitcher)
                      Padding(
                        padding: const EdgeInsets.only(bottom: MiraiTokens.spaceMd),
                        child: SegmentedButton<UserPersona>(
                          segments: const [
                            ButtonSegment(value: UserPersona.child, label: Text('Barn')),
                            ButtonSegment(value: UserPersona.adult, label: Text('Vuxen')),
                          ],
                          selected: {a.activePersona},
                          onSelectionChanged: (next) {
                            a.setActivePersona(next.first);
                          },
                        ),
                      ),
                    Text('Ditt bibliotek', style: tt.headlineLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w600)),
                    const SizedBox(height: MiraiTokens.spaceXs),
                    Text(
                      'Senaste dokument och sammanfattningar.',
                      style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                    ),
                    const SizedBox(height: MiraiTokens.spaceLg),
                    if (kUseFirestoreHomework &&
                        listeningStats != null &&
                        ownerUid.isNotEmpty) ...[
                      ListeningGoalHeader(uid: ownerUid, stats: listeningStats!),
                      const SizedBox(height: MiraiTokens.spaceLg),
                    ],
                    if (kUseFirestoreHomework) ...[
                      Builder(
                        builder: (context) {
                          final continueDoc = pickContinueListening(docs);
                          if (continueDoc == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: MiraiTokens.spaceLg),
                            child: _ContinueListeningCard(
                              doc: continueDoc,
                              repository: repository,
                            ),
                          );
                        },
                      ),
                      Builder(
                        builder: (context) {
                          final queue = buildListeningQueue(docs);
                          if (queue.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: MiraiTokens.spaceLg),
                            child: OutlinedButton.icon(
                              onPressed: () => showListeningQueueSheet(
                                context,
                                queue: queue,
                                repository: repository,
                                useCloudVoice: true,
                              ),
                              icon: const Icon(Icons.playlist_play_rounded),
                              label: Text('Spela upp oläst (${queue.length})'),
                            ),
                          );
                        },
                      ),
                    ],
                    if (docs.isEmpty)
                      Text('Inga dokument än. Lägg till ett nytt.', style: tt.bodyMedium)
                    else
                      ...docs.take(3).map((d) => Padding(
                            padding: const EdgeInsets.only(bottom: MiraiTokens.spaceSm),
                            child: ListTile(
                              tileColor: MiraiTokens.bgRaised,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                                side: const BorderSide(color: MiraiTokens.borderSubtle),
                              ),
                              title: Text(d.title),
                              subtitle: Text(documentTypeVisual(d.sourceType).label),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => DocumentDetailScreen(
                                      repository: repository,
                                      ownerUid: ownerUid,
                                      documentId: d.id,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )),
                    const SizedBox(height: MiraiTokens.spaceMd),
                    FilledButton.icon(
                      onPressed: () => showDocumentAddMenu(
                        context,
                        repository: repository,
                        ownerUid: ownerUid,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Nytt dokument'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ContinueListeningCard extends StatelessWidget {
  const _ContinueListeningCard({required this.doc, required this.repository});

  final UserDocument doc;
  final DocumentRepository repository;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pct = (doc.readingProgress.clamp(0.0, 1.0) * 100).round();
    return Container(
      padding: const EdgeInsets.all(MiraiTokens.spaceMd),
      decoration: BoxDecoration(
        color: MiraiTokens.bgRaised,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        border: Border.all(color: MiraiTokens.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fortsätt lyssna',
                  style: tt.labelSmall?.copyWith(
                    color: MiraiTokens.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  doc.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: MiraiTokens.spaceXs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
                  child: LinearProgressIndicator(
                    value: doc.readingProgress.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: MiraiTokens.bgInteractive,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Lyssnat $pct%', style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary)),
              ],
            ),
          ),
          const SizedBox(width: MiraiTokens.spaceSm),
          Material(
            color: MiraiTokens.accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                showAudioPlayerSheet(
                  context,
                  title: doc.title,
                  docId: doc.id,
                  load: () => AiService().documentAudio(documentId: doc.id),
                  initialProgress: doc.readingProgress,
                  onPositionChanged: (position, duration, completed) {
                    final progress = completed
                        ? 1.0
                        : computeReadingProgress(position: position, duration: duration);
                    repository.update(
                      doc.copyWith(readingProgress: progress, lastReadAt: DateTime.now()),
                    );
                  },
                );
              },
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.play_arrow_rounded, color: MiraiTokens.textInverse),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
