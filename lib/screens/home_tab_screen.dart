import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/deck_repository.dart';
import '../data/homework_repository.dart';
import '../data/xp_repository.dart';
import '../models/flashcard.dart';
import '../models/homework_item.dart';
import '../models/flashcard_deck.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/spaced_repetition.dart';
import '../services/todays_pass.dart';
import '../services/xp_rules.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../theme/subject_colors.dart';
import '../util/home_picker.dart';
import '../util/homework_listenable_text.dart';
import '../util/study_streak.dart';
import '../util/weekly_xp.dart';
import '../widgets/premium_listening_sheet.dart';
import '../widgets/reminder_settings_row.dart';
import '../widgets/session_duration_picker.dart';
import '../widgets/tts_player_sheet.dart';
import 'flashcard_deck_screen.dart';
import '../data/local_homework_repository.dart';
import 'school_letter_import_screen.dart';
import 'homework_detail_screen.dart';
import 'homework_create_flow_screen.dart';
import 'homework_snap_flow_screen.dart';
import 'exam_setup_screen.dart';
import 'study_session_screen.dart';

class HomeTabScreen extends StatefulWidget {
  const HomeTabScreen({
    super.key,
    required this.repository,
    this.deckRepository,
    this.authService,
    this.xpRepository,
    required this.familyId,
    required this.assignedToUserId,
    required this.onOpenHomework,
    required this.onSignOut,
  });

  final HomeworkRepository repository;
  final DeckRepository? deckRepository;
  final AuthService? authService;
  final XpRepository? xpRepository;
  final String familyId;
  final String assignedToUserId;
  final VoidCallback onOpenHomework;
  final Future<void> Function() onSignOut;

  @override
  State<HomeTabScreen> createState() => _HomeTabScreenState();
}

class _HomeTabScreenState extends State<HomeTabScreen> {
  Future<void> _openDetail(HomeworkItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HomeworkDetailScreen(
          repository: widget.repository,
          deckRepository: widget.deckRepository,
          familyId: widget.familyId,
          assignedToUserId: widget.assignedToUserId,
          homeworkId: item.id,
          authService: widget.authService,
        ),
      ),
    );
  }

  Future<void> _onRefresh() async {
    // Repository saknar explicit refresh-API; vi triggar rebuild.
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logga ut?'),
        content: const Text('Du kommer tillbaka till inloggningsskärmen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logga ut'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.onSignOut();
    }
  }

  Future<void> _openProfileMenu() async {
    final tt = Theme.of(context).textTheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MiraiTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.repository is LocalHomeworkRepository ? 'På den här enheten' : 'Konto', style: tt.titleMedium),
              const SizedBox(height: MiraiTokens.spaceSm),
              if (widget.authService?.savedPersona == UserPersona.both) ...[
                Text(
                  'Visningsläge',
                  style: tt.labelSmall?.copyWith(color: MiraiTokens.textTertiary),
                ),
                const SizedBox(height: 6),
                SegmentedButton<UserPersona>(
                  segments: const [
                    ButtonSegment(value: UserPersona.child, label: Text('Barn')),
                    ButtonSegment(value: UserPersona.adult, label: Text('Vuxen')),
                  ],
                  selected: {widget.authService!.activePersona},
                  onSelectionChanged: (next) {
                    setState(() => widget.authService!.setActivePersona(next.first));
                    Navigator.of(ctx).pop();
                  },
                ),
                const SizedBox(height: MiraiTokens.spaceMd),
              ],
              const ReminderSettingsRow(),
              const SizedBox(height: MiraiTokens.spaceMd),
              if (widget.repository is! LocalHomeworkRepository) OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _confirmSignOut();
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logga ut'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HomeworkItem>>(
      stream: widget.repository.watchForFamily(
        familyId: widget.familyId,
        assignedToUserId: widget.assignedToUserId,
      ),
      builder: (context, snap) {
        final local = widget.repository;
        final rawItems = snap.data ?? const <HomeworkItem>[];
        final items = kUseFirestoreHomework
            ? rawItems.where((h) => !h.id.startsWith('dev-')).toList()
            : rawItems;
        debugPrint(
          '[Home] received ${items.length} items, ${items.where((i) => i.status != HomeworkStatus.done).length} active',
        );
        final tt = Theme.of(context).textTheme;
        final now = DateTime.now();
        final buckets = pickHomeForHome(items, now);
        final next = buckets.next;
        final greeting = _greeting(now.hour);
        final dateLabel = _dateLabel(now);
        final greetingText = greeting;

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: MiraiContentPanel(
                child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: MiraiTokens.spaceLg,
                      vertical: MiraiTokens.spaceMd,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dateLabel.toUpperCase(),
                                    style: tt.labelSmall?.copyWith(
                                      letterSpacing: 0.5,
                                      color: MiraiTokens.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    greetingText,
                                    style: tt.headlineLarge?.copyWith(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'My Mirai',
                                    style: tt.bodySmall?.copyWith(
                                      color: MiraiTokens.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: MiraiTokens.spaceSm),
                            Material(
                              color: MiraiTokens.bgRaised,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _openProfileMenu,
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Center(
                                    child: _profileGlyph(null, tt),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (local is LocalHomeworkRepository) ...[
                          const SizedBox(height: MiraiTokens.spaceMd),
                          Card(child: ListTile(
                            leading: const Icon(Icons.mark_email_unread_outlined),
                            title: const Text('Läxor från veckobrev'),
                            subtitle: const Text('Hämta från Vardag eller klistra in ett brev'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => SchoolLetterImportScreen(repository: local,
                                familyId: widget.familyId, uid: widget.assignedToUserId))),
                          )),
                        ],
                        if (local is! LocalHomeworkRepository && widget.authService?.activePersona == UserPersona.child &&
                            widget.xpRepository != null) ...[
                          const SizedBox(height: MiraiTokens.spaceMd),
                          _XpRow(
                            xpRepository: widget.xpRepository!,
                            uid: widget.assignedToUserId,
                          ),
                        ],
                        const SizedBox(height: MiraiTokens.spaceLg),
                        if (widget.authService?.savedPersona == UserPersona.both) ...[
                          SegmentedButton<UserPersona>(
                            segments: const [
                              ButtonSegment(value: UserPersona.child, label: Text('Barn')),
                              ButtonSegment(value: UserPersona.adult, label: Text('Vuxen')),
                            ],
                            selected: {widget.authService!.activePersona},
                            onSelectionChanged: (next) {
                              setState(() => widget.authService!.setActivePersona(next.first));
                            },
                          ),
                          const SizedBox(height: MiraiTokens.spaceLg),
                        ],
                        if (next == null)
                          _EmptyHomeworkState(
                            hasCompleted: items.any((h) => h.status == HomeworkStatus.done),
                            onCreate: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => HomeworkCreateFlowScreen(
                                    repository: widget.repository,
                                    deckRepository: widget.deckRepository,
                                    familyId: widget.familyId,
                                    assignedToUserId: widget.assignedToUserId,
                                    authService: widget.authService,
                                  ),
                                ),
                              );
                            },
                          )
                        else ...[
                          Text(
                            'NÄSTA'.toUpperCase(),
                            style: tt.labelSmall?.copyWith(
                              color: MiraiTokens.textTertiary,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: MiraiTokens.spaceSm),
                          _NextDeckWrapper(
                            item: next,
                            deckRepository: widget.deckRepository,
                            now: now,
                            xpRepository: widget.xpRepository,
                            uid: widget.assignedToUserId,
                            onOpenDetail: () => _openDetail(next),
                            onCloudStory: () => showPremiumListeningSheet(
                              context,
                              titleHint: next.title,
                              load: () => AiService().listeningStory(
                                    homeworkId: next.id,
                                  ),
                            ),
                          ),
                        ],
                        if (widget.authService?.activePersona == UserPersona.child &&
                            widget.deckRepository != null) ...[
                          const SizedBox(height: MiraiTokens.spaceLg),
                          _DailyPassCard(
                            deckRepository: widget.deckRepository!,
                            xpRepository: widget.xpRepository,
                            uid: widget.assignedToUserId,
                          ),
                        ],
                        if (buckets.today.isNotEmpty) ...[
                          const SizedBox(height: MiraiTokens.spaceLg),
                          Text(
                            'Idag och imorgon',
                            style: tt.titleSmall?.copyWith(
                              color: MiraiTokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: MiraiTokens.spaceSm),
                          Container(
                            decoration: BoxDecoration(
                              color: MiraiTokens.bgRaised,
                              borderRadius:
                                  BorderRadius.circular(MiraiTokens.radiusLg),
                              border: Border.all(
                                color: MiraiTokens.borderSubtle,
                                width: MiraiTokens.borderThin,
                              ),
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < buckets.today.length; i++) ...[
                                  _TodayRow(
                                    item: buckets.today[i],
                                    onTap: () => _openDetail(buckets.today[i]),
                                  ),
                                  if (i < buckets.today.length - 1)
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      indent: 24,
                                      color: MiraiTokens.borderSubtle,
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (buckets.week.isNotEmpty) ...[
                          const SizedBox(height: MiraiTokens.spaceSm),
                          Theme(
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                            ),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              initiallyExpanded: false,
                              title: Text(
                                'Den här veckan (${buckets.week.length} läxor)',
                                style: tt.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: MiraiTokens.textPrimary,
                                ),
                              ),
                              childrenPadding: EdgeInsets.zero,
                              children: [
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: MiraiTokens.bgRaised,
                                    borderRadius: BorderRadius.circular(
                                      MiraiTokens.radiusLg,
                                    ),
                                    border: Border.all(
                                      color: MiraiTokens.borderSubtle,
                                      width: MiraiTokens.borderThin,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < buckets.week.length; i++) ...[
                                        _TodayRow(
                                          item: buckets.week[i],
                                          onTap: () => _openDetail(buckets.week[i]),
                                        ),
                                        if (i < buckets.week.length - 1)
                                          const Divider(
                                            height: 1,
                                            thickness: 1,
                                            indent: 24,
                                            color: MiraiTokens.borderSubtle,
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: MiraiTokens.spaceXl),
                        if (local is! LocalHomeworkRepository || next != null) _HomeQuickActions(
                          repository: widget.repository,
                          deckRepository: widget.deckRepository,
                          familyId: widget.familyId,
                          assignedToUserId: widget.assignedToUserId,
                          authService: widget.authService,
                          xpRepository: widget.xpRepository,
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: MiraiTokens.spaceLg),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: MiraiTokens.spaceSm,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: MiraiTokens.bgRaised,
                              borderRadius:
                                  BorderRadius.circular(MiraiTokens.radiusSm),
                            ),
                            child: Text(
                              'debug · familyId: ${_shortFamily(widget.familyId)}',
                              style: tt.bodySmall?.copyWith(
                                color: MiraiTokens.textTertiary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _XpRow extends StatelessWidget {
  const _XpRow({required this.xpRepository, required this.uid});

  final XpRepository xpRepository;
  final String uid;

  void _openWeekSheet(BuildContext context, Map<String, int> xpByDay) {
    final tt = Theme.of(context).textTheme;
    final days = weeklyXpBreakdown(dayInWeek: DateTime.now(), xpByDay: xpByDay);
    const labels = ['Mån', 'Tis', 'Ons', 'Tors', 'Fre', 'Lör', 'Sön'];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MiraiTokens.spaceLg,
            MiraiTokens.spaceSm,
            MiraiTokens.spaceLg,
            MiraiTokens.spaceLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Den här veckan', style: tt.titleMedium),
              const SizedBox(height: MiraiTokens.spaceSm),
              for (var i = 0; i < days.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 48, child: Text(labels[i], style: tt.bodyMedium)),
                      Expanded(
                        child: Text(
                          days[i].xp > 0 ? '${days[i].xp} ⭐' : '–',
                          style: tt.bodyMedium?.copyWith(
                            color: days[i].xp > 0
                                ? MiraiTokens.textPrimary
                                : MiraiTokens.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return StreamBuilder<int>(
      stream: xpRepository.watchXpTotal(uid),
      builder: (context, totalSnap) {
        return StreamBuilder<Map<String, int>>(
          stream: xpRepository.watchXpByDay(uid),
          builder: (context, dayMapSnap) {
            final total = totalSnap.data ?? 0;
            final xpByDay = dayMapSnap.data ?? const <String, int>{};
            final weekTotal = weeklyXpTotal(dayInWeek: DateTime.now(), xpByDay: xpByDay);
            final progress = (weekTotal / XpRules.weeklyGoal).clamp(0.0, 1.0);
            final streak = computeStudyStreakDays(
              todayLocal: DateTime.now(),
              xpByDay: xpByDay,
            );
            return InkWell(
              borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
              onTap: () => _openWeekSheet(context, xpByDay),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text('⭐ $total', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (streak > 0) ...[
                      const SizedBox(width: MiraiTokens.spaceSm),
                      Text(
                        streak == 1 ? '🔥 1 dag i rad' : '🔥 $streak dagar i rad',
                        style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
                      ),
                    ],
                    const SizedBox(width: MiraiTokens.spaceSm),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: MiraiTokens.bgInteractive,
                          color: MiraiTokens.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: MiraiTokens.spaceXs),
                    Text(
                      '$weekTotal/${XpRules.weeklyGoal}',
                      style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// NÄSTA på Hem — **Studera** när den länkade leken har due-kort (SM‑2).
class _NextDeckWrapper extends StatelessWidget {
  const _NextDeckWrapper({
    required this.item,
    required this.deckRepository,
    required this.now,
    required this.onOpenDetail,
    required this.onCloudStory,
    this.xpRepository,
    this.uid,
  });

  final HomeworkItem item;
  final DeckRepository? deckRepository;
  final DateTime now;
  final XpRepository? xpRepository;
  final String? uid;
  final VoidCallback onOpenDetail;
  final VoidCallback onCloudStory;

  @override
  Widget build(BuildContext context) {
    final dr = deckRepository;
    final deckId = (item.linkedDeckId ?? '').trim();
    if (dr == null || deckId.isEmpty) {
      return _NextCard(
        item: item,
        now: now,
        onOpen: onOpenDetail,
        onCloudStory: onCloudStory,
      );
    }
    return StreamBuilder<List<Flashcard>>(
      stream: dr.watchCardsInDeck(deckId),
      builder: (context, snap) {
        int? due;
        if (snap.hasData) {
          due = SpacedRepetition.filterDue(snap.data!, DateTime.now()).length;
        }
        VoidCallback? onStudy;
        if (due != null && due > 0) {
          onStudy = () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FlashcardDeckScreen(
                  deckRepository: dr,
                  deckId: deckId,
                  xpRepository: xpRepository,
                  uid: uid,
                  isChildMode: true,
                ),
              ),
            );
          };
        }
        return _NextCard(
          item: item,
          now: now,
          onOpen: onOpenDetail,
          onCloudStory: onCloudStory,
          studyDueCount: due,
          onStudyFlashcards: onStudy,
        );
      },
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.item,
    required this.now,
    required this.onOpen,
    required this.onCloudStory,
    this.studyDueCount,
    this.onStudyFlashcards,
  });

  final HomeworkItem item;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onCloudStory;
  final int? studyDueCount;
  final VoidCallback? onStudyFlashcards;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subject = _capitalize(item.subject.trim());
    final handIn = _handInDeadlineLine(item, now);
    final canListen = listenableHomeworkText(item) != null;
    final wantsStudy =
        onStudyFlashcards != null &&
        studyDueCount != null &&
        studyDueCount! > 0;

    return Material(
      color: MiraiTokens.bgRaised,
      borderRadius: BorderRadius.circular(MiraiTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusLg),
        onTap: onOpen,
        child: Container(
      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
      decoration: BoxDecoration(
        color: MiraiTokens.bgRaised,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusLg),
        border: Border.all(
          color: MiraiTokens.borderSubtle,
          width: MiraiTokens.borderThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(
              horizontal: MiraiTokens.spaceXs,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
            ),
            child: Text(
              subject,
              style: tt.labelMedium?.copyWith(color: MiraiTokens.textSecondary),
            ),
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.titleLarge?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: MiraiTokens.spaceXs),
          Text(
            handIn,
            style: tt.bodyMedium?.copyWith(color: MiraiTokens.textSecondary),
          ),
          if (wantsStudy) ...[
            const SizedBox(height: MiraiTokens.spaceSm),
            Row(
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  size: 18,
                  color: MiraiTokens.accent,
                ),
                const SizedBox(width: MiraiTokens.spaceXs),
                Expanded(
                  child: Text(
                    studyDueCount == 1
                        ? '1 kort väntar på repetition.'
                        : '$studyDueCount kort väntar på repetition.',
                    style: tt.bodyMedium?.copyWith(
                      color: MiraiTokens.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: MiraiTokens.spaceLg),
          SizedBox(
            width: double.infinity,
            child: wantsStudy
                ? FilledButton.icon(
                    onPressed: onStudyFlashcards,
                    icon: const Icon(Icons.style_rounded),
                    label: Text(
                      'Träna ($studyDueCount kort)',
                    ),
                  )
                : FilledButton.icon(
                    onPressed: canListen
                        ? () {
                            final text = listenableHomeworkText(item);
                            if (text == null || text.trim().isEmpty) return;
                            showTtsPlayer(
                              context,
                              text: text,
                              title: item.title,
                              subject: item.subject,
                            );
                          }
                        : onOpen,
                    icon: Icon(canListen ? Icons.headphones_rounded : Icons.open_in_new_rounded),
                    label: Text(
                      canListen ? 'Lyssna' : 'Öppna',
                    ),
                  ),
          ),
          if (wantsStudy || canListen) ...[
            const SizedBox(height: MiraiTokens.spaceSm),
            Row(
              children: [
                if (canListen && wantsStudy)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final text = listenableHomeworkText(item);
                        if (text == null || text.trim().isEmpty) return;
                        showTtsPlayer(
                          context,
                          text: text,
                          title: item.title,
                          subject: item.subject,
                        );
                      },
                      icon: const Icon(Icons.headphones_rounded),
                      label: const Text('Lyssna'),
                    ),
                  ),
                if (canListen && wantsStudy)
                  const SizedBox(width: MiraiTokens.spaceSm),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text('Öppna'),
                  ),
                ),
              ],
            ),
          ],
          if (canListen && kUseFirestoreHomework) ...[
            const SizedBox(height: MiraiTokens.spaceSm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCloudStory,
                icon: const Icon(Icons.cloud_rounded, size: 20),
                label: const Text('Saga (molnröst)'),
              ),
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }
}

/// AO-11: "Dagens pass" — alla due-kort ur familjens lekar, blandade.
class _DailyPassCard extends StatefulWidget {
  const _DailyPassCard({
    required this.deckRepository,
    this.xpRepository,
    required this.uid,
  });

  final DeckRepository deckRepository;
  final XpRepository? xpRepository;
  final String uid;

  @override
  State<_DailyPassCard> createState() => _DailyPassCardState();
}

class _DailyPassCardState extends State<_DailyPassCard> {
  Future<void> _start(List<FlashcardDeck> decks) async {
    final allCards = <Flashcard>[];
    for (final d in decks) {
      allCards.addAll(await widget.deckRepository.watchCardsInDeck(d.id).first);
    }
    final cards = buildTodaysPass(decks: decks, allCards: allCards, now: DateTime.now());
    if (!mounted || cards.isEmpty) return;

    final minutes = await showSessionDurationPicker(context);
    if (!mounted) return;

    final subjectByDeckId = <String, String>{};
    for (final d in decks) {
      final s = d.subject?.trim();
      subjectByDeckId[d.id] = (s == null || s.isEmpty) ? 'Okänt ämne' : s;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudySessionScreen(
          deckRepository: widget.deckRepository,
          cards: cards,
          deck: null,
          subjectByDeckId: subjectByDeckId,
          examDeckCount: decks.length,
          xpRepository: widget.xpRepository,
          uid: widget.uid,
          sessionDurationMinutes: minutes,
        ),
      ),
    );
  }

  Future<int> _dueCount(List<FlashcardDeck> decks) async {
    final allCards = <Flashcard>[];
    for (final d in decks) {
      allCards.addAll(await widget.deckRepository.watchCardsInDeck(d.id).first);
    }
    return SpacedRepetition.filterDue(allCards, DateTime.now()).length;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FlashcardDeck>>(
      stream: widget.deckRepository.watchDecksForFamily(),
      builder: (context, deckSnap) {
        final decks = deckSnap.data ?? const <FlashcardDeck>[];
        if (decks.isEmpty) return const SizedBox.shrink();
        return FutureBuilder<int>(
          future: _dueCount(decks),
          builder: (context, dueSnap) {
            final dueCount = dueSnap.data ?? 0;
            if (dueCount == 0) return const SizedBox.shrink();
            return SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _start(decks),
                icon: const Icon(Icons.today_rounded),
                label: Text('Dagens pass – $dueCount kort'),
              ),
            );
          },
        );
      },
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({
    required this.repository,
    this.deckRepository,
    required this.familyId,
    required this.assignedToUserId,
    this.authService,
    this.xpRepository,
  });

  final HomeworkRepository repository;
  final DeckRepository? deckRepository;
  final String familyId;
  final String assignedToUserId;
  final AuthService? authService;
  final XpRepository? xpRepository;

  @override
  Widget build(BuildContext context) {
    final dr = deckRepository;
    final canOpenDeckTools = dr != null;
    if (repository is LocalHomeworkRepository) {
      return OutlinedButton.icon(icon: const Icon(Icons.edit_outlined),
        label: const Text('Skriv en egen läxa'), onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => HomeworkCreateFlowScreen(repository: repository,
            familyId: familyId, assignedToUserId: assignedToUserId, authService: authService))));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Snabbåtgärder'.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: MiraiTokens.textTertiary,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: MiraiTokens.spaceSm),
        Container(
          padding: const EdgeInsets.all(MiraiTokens.spaceSm),
          decoration: BoxDecoration(
            color: MiraiTokens.bgRaised,
            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            border: Border.all(
              color: MiraiTokens.borderSubtle,
              width: MiraiTokens.borderThin,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _QuickActionItem(
                  icon: Icons.camera_alt_outlined,
                  label: 'Fota läxan',
                  subtitle: 'Läs in text eller uppgifter',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HomeworkSnapFlowScreen(
                          repository: repository,
                          deckRepository: dr,
                          familyId: familyId,
                          assignedToUserId: assignedToUserId,
                          authService: authService,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: MiraiTokens.spaceXs),
              Expanded(
                child: _QuickActionItem(
                  icon: Icons.add_rounded,
                  label: 'Ny läxa',
                  subtitle: 'Skriv in för hand',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HomeworkCreateFlowScreen(
                          repository: repository,
                          deckRepository: dr,
                          familyId: familyId,
                          assignedToUserId: assignedToUserId,
                          authService: authService,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: MiraiTokens.spaceXs),
              Expanded(
                child: _QuickActionItem(
                  icon: Icons.school_outlined,
                  label: 'Plugga inför prov',
                  subtitle: 'Blanda lekar och förhör',
                  enabled: canOpenDeckTools,
                  onTap: () {
                    if (dr == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExamSetupScreen(
                          deckRepository: dr,
                          xpRepository: xpRepository,
                          uid: assignedToUserId,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: MiraiTokens.spaceXs),
              Expanded(
                child: _QuickActionItem(
                  icon: Icons.quiz_outlined,
                  label: 'Gör ett förhör',
                  subtitle: 'Fota glosor och förhör direkt',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HomeworkSnapFlowScreen(
                          repository: repository,
                          deckRepository: dr,
                          familyId: familyId,
                          assignedToUserId: assignedToUserId,
                          authService: authService,
                          intent: SnapIntent.quiz,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActionItem extends StatelessWidget {
  const _QuickActionItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final textColor = enabled ? MiraiTokens.textSecondary : MiraiTokens.textTertiary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MiraiTokens.spaceXs,
            vertical: MiraiTokens.spaceSm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: textColor),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: MiraiTokens.textTertiary,
                        fontSize: 10,
                        height: 1.2,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _handInDeadlineLine(HomeworkItem h, DateTime now) {
  if (h.dueAt == null) return 'Ingen deadline satt';
  final today = homeworkDay(now);
  final d1 = homeworkDay(h.dueAt!);
  final diff = d1.difference(today).inDays;
  if (diff < 0) {
    final a = -diff;
    return a == 1
        ? 'Förfallen i går'
        : 'Förfallen för $a dagar sedan';
  }
  if (diff == 0) return 'Lämnas in idag';
  if (diff == 1) return 'Lämnas in imorgon';
  if (diff <= 7) return 'Lämnas in om $diff dagar';
  return 'Lämnas in ${_compactDateSv(h.dueAt!)}';
}

String _compactDateSv(DateTime d) =>
    '${d.day}/${d.month}';

class _TodayRow extends StatelessWidget {
  const _TodayRow({
    required this.item,
    required this.onTap,
  });

  final HomeworkItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: MiraiTokens.spaceSm,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: subjectAccentColor(item.subject),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: MiraiTokens.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: MiraiTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_shortDeadline(item.dueAt)} · ${_capitalize(item.subject.trim())}',
                    style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: MiraiTokens.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHomeworkState extends StatelessWidget {
  const _EmptyHomeworkState({
    required this.onCreate,
    required this.hasCompleted,
  });

  final bool hasCompleted;

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MiraiTokens.space2xl),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 56,
              color: MiraiTokens.accent,
            ),
            const SizedBox(height: MiraiTokens.spaceMd),
            Text(
              hasCompleted ? 'Alla läxor klara' : 'Inga läxor än',
              style: tt.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MiraiTokens.spaceXs),
            Text(
              hasCompleted ? 'Dina färdiga läxor finns under Läxor → Klara.' : 'Lägg till första läxan så börjar vi.',
              style: tt.bodyMedium?.copyWith(color: MiraiTokens.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MiraiTokens.spaceLg),
            FilledButton(
              onPressed: onCreate,
              child: const Text('Lägg till läxa'),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _profileGlyph(String? displayName, TextTheme tt) {
  final trimmed = displayName?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    final initial = trimmed.substring(0, 1).toUpperCase();
    return Text(
      initial,
      style: tt.labelLarge?.copyWith(
        color: MiraiTokens.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
  return const Icon(Icons.person_outline_rounded, size: 20);
}

String _dateLabel(DateTime d) {
  const weekdays = [
    'Måndag',
    'Tisdag',
    'Onsdag',
    'Torsdag',
    'Fredag',
    'Lördag',
    'Söndag',
  ];
  const months = [
    'januari',
    'februari',
    'mars',
    'april',
    'maj',
    'juni',
    'juli',
    'augusti',
    'september',
    'oktober',
    'november',
    'december',
  ];
  return '${weekdays[d.weekday - 1]} · ${d.day} ${months[d.month - 1]}';
}

String _greeting(int hour) {
  if (hour < 11) return 'God morgon';
  if (hour < 18) return 'God dag';
  return 'God kväll';
}

String _shortFamily(String familyId) {
  if (familyId.length <= 8) return familyId;
  return '${familyId.substring(0, 8)}…';
}

String _shortDeadline(DateTime? dueAt) {
  if (dueAt == null) return 'Ingen deadline';
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  final d1 = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final diff = d1.difference(d0).inDays;
  if (diff == 0) return 'Idag';
  if (diff == 1) return 'Imorgon';
  if (diff > 1 && diff <= 6) return 'Om $diff dagar';
  return _dateLabel(dueAt);
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

