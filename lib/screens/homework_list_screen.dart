import 'package:flutter/material.dart';

import '../config.dart';
import '../data/local_homework_repository.dart';
import 'school_letter_import_screen.dart';
import '../data/deck_repository.dart';
import '../data/homework_repository.dart';
import '../models/homework_item.dart';
import '../services/auth_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../theme/subject_colors.dart';
import '../util/homework_listenable_text.dart';
import '../widgets/tts_player_sheet.dart';
import 'homework_create_flow_screen.dart';
import 'homework_detail_screen.dart';
import 'homework_snap_flow_screen.dart';

enum _HomeworkListMode {
  active,
  bySubject,
  done,
}

class HomeworkListScreen extends StatelessWidget {
  const HomeworkListScreen({
    super.key,
    required this.repository,
    this.deckRepository,
    required this.familyId,
    required this.assignedToUserId,
    this.authService,
  });

  final HomeworkRepository repository;
  final DeckRepository? deckRepository;
  final String familyId;
  final String assignedToUserId;
  final AuthService? authService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<HomeworkItem>>(
        stream: repository.watchForFamily(
          familyId: familyId,
          assignedToUserId: assignedToUserId,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Kunde inte läsa läxor.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rawItems = snapshot.data!;
          final items = kUseFirestoreHomework
              ? rawItems.where((h) => !h.id.startsWith('dev-')).toList()
              : rawItems;
          return _HomeworkListBody(
            items: items,
            repository: repository,
            deckRepository: deckRepository,
            familyId: familyId,
            assignedToUserId: assignedToUserId,
            authService: authService,
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_list_new_homework',
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (repository is LocalHomeworkRepository)
                    ListTile(leading: const Icon(Icons.mark_email_unread_outlined),
                      title: const Text('Läxor från veckobrev'), onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SchoolLetterImportScreen(
                          repository: repository as LocalHomeworkRepository, familyId: familyId, uid: assignedToUserId)));
                      }),
                  if (repository is! LocalHomeworkRepository) ListTile(
                    leading: const Icon(Icons.quiz_outlined),
                    title: const Text('Gör ett förhör'),
                    subtitle: const Text('Fota glosor och förhör direkt'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HomeworkSnapFlowScreen(
                            repository: repository,
                            deckRepository: deckRepository,
                            familyId: familyId,
                            assignedToUserId: assignedToUserId,
                            authService: authService,
                            intent: SnapIntent.quiz,
                          ),
                        ),
                      );
                    },
                  ),
                  if (repository is! LocalHomeworkRepository) ListTile(
                    leading: const Icon(Icons.camera_alt_outlined),
                    title: const Text('Fota läxan'),
                    subtitle: const Text('AI läser och fyller i åt dig'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HomeworkSnapFlowScreen(
                            repository: repository,
                            deckRepository: deckRepository,
                            familyId: familyId,
                            assignedToUserId: assignedToUserId,
                            authService: authService,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Ny läxa'),
                    subtitle: const Text('Fyll i manuellt'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HomeworkCreateFlowScreen(
                            repository: repository,
                            deckRepository: deckRepository,
                            familyId: familyId,
                            assignedToUserId: assignedToUserId,
                            authService: authService,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ny läxa'),
      ),
    );
  }
}

class _HomeworkListBody extends StatefulWidget {
  const _HomeworkListBody({
    required this.items,
    required this.repository,
    this.deckRepository,
    required this.familyId,
    required this.assignedToUserId,
    this.authService,
  });

  final List<HomeworkItem> items;
  final HomeworkRepository repository;
  final DeckRepository? deckRepository;
  final String familyId;
  final String assignedToUserId;
  final AuthService? authService;

  @override
  State<_HomeworkListBody> createState() => _HomeworkListBodyState();
}

class _HomeworkListBodyState extends State<_HomeworkListBody> {
  _HomeworkListMode _mode = _HomeworkListMode.active;

  static bool _aktivaEligible(HomeworkItem h) =>
      h.status != HomeworkStatus.done && h.status != HomeworkStatus.archived;

  int _dueSort(HomeworkItem a, HomeworkItem b) {
    final ad = a.dueAt;
    final bd = b.dueAt;
    if (ad != null && bd != null) return ad.compareTo(bd);
    if (ad != null) return -1;
    if (bd != null) return 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  List<HomeworkItem> _activeList() {
    final a = widget.items.where(_aktivaEligible).toList()
      ..sort(_dueSort);
    return a;
  }

  List<HomeworkItem> _doneList() {
    final d = widget.items.where((h) => h.status == HomeworkStatus.done).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (d.length > 50) return d.sublist(0, 50);
    return d;
  }

  String _subjectLabel(String subject) {
    final t = subject.trim();
    if (t.isEmpty) return 'Övrigt';
    return '${t[0].toUpperCase()}${t.length > 1 ? t.substring(1) : ''}';
  }

  Widget _homeworkTile(HomeworkItem h, {required bool faded}) {
    return Material(
      color: MiraiTokens.bgRaised,
      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HomeworkDetailScreen(
                repository: widget.repository,
                deckRepository: widget.deckRepository,
                familyId: widget.familyId,
                assignedToUserId: widget.assignedToUserId,
                homeworkId: h.id,
                authService: widget.authService,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            border: Border.all(
              color: MiraiTokens.borderSubtle,
              width: MiraiTokens.borderThin,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: subjectAccentColor(h.subject),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: MiraiTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: faded
                                ? MiraiTokens.textTertiary
                                : MiraiTokens.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      h.status == HomeworkStatus.done
                          ? 'Klar'
                          : '${_shortDeadline(h.dueAt)} · ${_subjectLabel(h.subject)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            color: MiraiTokens.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MiraiTokens.spaceXs),
              _ListenButton(item: h),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: MiraiTokens.textTertiary,
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
    if (widget.items.isEmpty) {
      return MiraiContentPanel(
        alignment: Alignment.center,
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.auto_stories_outlined,
                size: 48,
                color: MiraiTokens.textTertiary,
              ),
              const SizedBox(height: MiraiTokens.spaceMd),
              Text('Inga läxor än', style: tt.headlineSmall),
              const SizedBox(height: MiraiTokens.spaceXs),
              Text(
                'Tryck + för att lägga till',
                style:
                    tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
              ),
            ],
        ),
      );
    }

    final activeList = _activeList();
    final doneList = _doneList();
    final size = miraiWindowSizeOf(context);
    final cols = size.isAtLeastExpanded
        ? 3
        : (size.isAtLeastMedium ? 2 : 1);

    Widget tilesGrid(List<HomeworkItem> list, {required bool faded}) {
      if (cols == 1) {
        return Column(
          children: [
            for (final h in list) ...[
              _homeworkTile(h, faded: faded),
              const SizedBox(height: MiraiTokens.spaceSm),
            ],
          ],
        );
      }
      return LayoutBuilder(
        builder: (ctx, c) {
          final spacing = MiraiTokens.spaceSm * (cols - 1);
          final width = c.maxWidth.isFinite
              ? (c.maxWidth - spacing) / cols
              : 320.0;
          return Wrap(
            spacing: MiraiTokens.spaceSm,
            runSpacing: MiraiTokens.spaceSm,
            children: [
              for (final h in list)
                SizedBox(
                  width: width,
                  child: _homeworkTile(h, faded: faded),
                ),
            ],
          );
        },
      );
    }

    List<Widget> bodyChildren() {
      switch (_mode) {
        case _HomeworkListMode.active:
          if (activeList.isEmpty) {
            return [
              Text(
                'Inga aktiva läxor.',
                style: tt.bodyMedium?.copyWith(color: MiraiTokens.textTertiary),
              ),
            ];
          }
          return [tilesGrid(activeList, faded: false)];
        case _HomeworkListMode.done:
          if (doneList.isEmpty) {
            return [
              Text(
                'Inga klara läxor än.',
                style: tt.bodyMedium?.copyWith(color: MiraiTokens.textTertiary),
              ),
            ];
          }
          return [tilesGrid(doneList, faded: true)];
        case _HomeworkListMode.bySubject:
          if (activeList.isEmpty) {
            return [
              Text(
                'Inga läxor att gruppera per ämne.',
                style: tt.bodyMedium?.copyWith(color: MiraiTokens.textTertiary),
              ),
            ];
          }
          final map = <String, List<HomeworkItem>>{};
          for (final h in activeList) {
            final key = _subjectLabel(h.subject);
            map.putIfAbsent(key, () => []).add(h);
          }
          final keys = map.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return [
            for (final key in keys) ...[
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding:
                      const EdgeInsets.only(bottom: MiraiTokens.spaceSm),
                  title: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: subjectAccentColor(
                            map[key]!.first.subject,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: MiraiTokens.spaceSm),
                      Expanded(
                        child: Text(
                          key,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${map[key]!.length}',
                        style:
                            tt.labelSmall?.copyWith(color: MiraiTokens.textTertiary),
                      ),
                    ],
                  ),
                  children: [
                    for (final h in map[key]!) ...[
                      _homeworkTile(h, faded: false),
                      const SizedBox(height: MiraiTokens.spaceSm),
                    ],
                  ],
                ),
              ),
            ],
          ];
      }
    }

    return SafeArea(
      child: MiraiContentPanel(
        wide: true,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(
              MiraiTokens.spaceLg,
              MiraiTokens.spaceLg,
              MiraiTokens.spaceLg,
              100,
            ),
            children: [
              Text(
                'Läxor',
                style: tt.headlineLarge?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: MiraiTokens.spaceMd),
              SegmentedButton<_HomeworkListMode>(
                segments: const [
                  ButtonSegment(
                    value: _HomeworkListMode.active,
                    label: Text('Aktiva'),
                    icon: Icon(Icons.pending_actions_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: _HomeworkListMode.bySubject,
                    label: Text('Per ämne'),
                    icon: Icon(Icons.category_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: _HomeworkListMode.done,
                    label: Text('Klara'),
                    icon: Icon(Icons.check_circle_outline, size: 18),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) =>
                    setState(() => _mode = s.single),
              ),
              const SizedBox(height: MiraiTokens.spaceLg),
              ...bodyChildren(),
            ],
        ),
      ),
    );
  }
}

class _ListenButton extends StatelessWidget {
  const _ListenButton({required this.item});
  final HomeworkItem item;

  @override
  Widget build(BuildContext context) {
    final text = listenableHomeworkText(item);
    final enabled = text != null && text.trim().isNotEmpty;
    final playableText = text ?? '';
    return Material(
      color: MiraiTokens.bgInteractive,
      shape: const CircleBorder(),
      child: Tooltip(
        message: enabled ? 'Lyssna' : 'Lägg till text eller sammanfattning först',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled
              ? () {
                  showTtsPlayer(
                    context,
                    text: playableText,
                    title: item.title,
                    subject: item.subject,
                  );
                }
              : null,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              Icons.headphones_rounded,
              size: 14,
              color: enabled ? MiraiTokens.textSecondary : MiraiTokens.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
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
  return '${dueAt.day}/${dueAt.month}';
}
