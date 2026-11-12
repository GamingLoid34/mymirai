import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../config.dart';
import '../data/local_homework_repository.dart';
import 'school_letter_import_screen.dart';
import '../data/deck_repository.dart';
import '../data/document_repository.dart';
import '../data/firestore_listening_stats_repository.dart';
import '../data/homework_repository.dart';
import '../data/xp_repository.dart';
import '../models/homework_item.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../util/recording_settings.dart';
import '../util/share_intent_routing.dart';
import '../widgets/listening_stats_section.dart';
import 'adult_home_screen.dart';
import 'document_create_flow_screen.dart';
import 'documents_list_screen.dart';
import 'home_tab_screen.dart';
import 'homework_list_screen.dart';
import 'note_capture_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({
    super.key,
    required this.homeworkRepository,
    this.deckRepository,
    required this.documentRepository,
    this.listeningStatsRepository,
    this.xpRepository,
    required this.familyId,
    required this.assignedToUserId,
    required this.authService,
  });

  final HomeworkRepository homeworkRepository;
  final DeckRepository? deckRepository;
  final DocumentRepository documentRepository;
  final FirestoreListeningStatsRepository? listeningStatsRepository;
  final XpRepository? xpRepository;
  final String familyId;
  final String assignedToUserId;
  final AuthService authService;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;
  StreamSubscription<List<HomeworkItem>>? _reminderSub;
  String? _lastReminderSignature;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    _reminderSub = widget.homeworkRepository
        .watchForFamily(
          familyId: widget.familyId,
          assignedToUserId: widget.assignedToUserId,
        )
        .listen(_onHomeworkChangedForReminders);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initShareIntentHandling());
    }
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    _shareSub?.cancel();
    super.dispose();
  }

  /// Lyssna på varma delningar även medan användaren granskar en kallstart.
  Future<void> _initShareIntentHandling() async {
    final sharing = ReceiveSharingIntent.instance;
    _shareSub = sharing.getMediaStream().listen((files) {
      if (mounted && files.isNotEmpty) _handleSharedMedia(files);
    });
    final initial = await sharing.getInitialMedia();
    if (initial.isNotEmpty && mounted) {
      await sharing.reset();
      await _handleSharedMedia(initial);
    }
  }

  Future<void> _handleSharedMedia(List<SharedMediaFile> files) async {
    if (!mounted) return;
    final first = files.first;
    final decision = classifyShare(
      pluginType: first.type.value,
      mimeType: first.mimeType,
      text: first.path,
    );
    final repository = widget.homeworkRepository;
    if (widget.authService.activePersona != UserPersona.adult) {
      if (repository is LocalHomeworkRepository && decision.kind == ShareRouteKind.text) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SchoolLetterImportScreen(
          repository: repository, familyId: widget.familyId, uid: widget.assignedToUserId,
          initialText: decision.text ?? '')));
      } else if (repository is LocalHomeworkRepository) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dela brevets text eller hämta brevet från Vardag.')));
      }
      return;
    }
    final ownerUid = widget.authService.session?.uid ?? widget.assignedToUserId;
    switch (decision.kind) {
      case ShareRouteKind.url:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DocumentCreateFlowScreen(
              repository: widget.documentRepository,
              ownerUid: ownerUid,
              sharedUrl: decision.text,
            ),
          ),
        );
      case ShareRouteKind.text:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NoteCaptureScreen(
              repository: widget.documentRepository,
              ownerUid: ownerUid,
              initialText: decision.text,
            ),
          ),
        );
      case ShareRouteKind.file:
        try {
          final bytes = await File(first.path).readAsBytes();
          final name = first.path.split(RegExp(r'[\\/]')).last;
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DocumentCreateFlowScreen(
                repository: widget.documentRepository,
                ownerUid: ownerUid,
                sharedFileBytes: bytes,
                sharedFileName: name.isEmpty ? 'fil' : name,
              ),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          showFriendlySnack(
            context,
            'Hoppsan – det gick inte att läsa den delade filen. Testa igen.',
            error: e,
          );
        }
    }
  }

  void _onHomeworkChangedForReminders(List<HomeworkItem> items) {
    if (widget.authService.activePersona != UserPersona.child) return;
    final active = items.where((h) => h.status != HomeworkStatus.done).toList();
    final signature = active
        .map((h) => '${h.id}:${h.dueAt?.toIso8601String()}:${h.status.name}')
        .join('|');
    if (signature == _lastReminderSignature) return;
    _lastReminderSignature = signature;
    NotificationService.instance.syncDeadlineReminders(active);
  }

  int _effectiveShellIndex(bool adultMode) {
    final maxIdx = adultMode ? 2 : 1;
    return _index > maxIdx ? maxIdx : _index;
  }

  List<_ShellDest> _destinations(bool adultMode) {
    if (adultMode) {
      return const [
        _ShellDest(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Hem',
        ),
        _ShellDest(
          icon: Icon(Icons.library_books_outlined),
          selectedIcon: Icon(Icons.library_books),
          label: 'Dokument',
        ),
        _ShellDest(
          icon: Icon(Icons.tune_rounded),
          selectedIcon: Icon(Icons.tune),
          label: 'Mer',
        ),
      ];
    }
    return const [
      _ShellDest(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Hem',
      ),
      _ShellDest(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: 'Läxor',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final adultMode = widget.authService.activePersona == UserPersona.adult;
    final shellIndex = _effectiveShellIndex(adultMode);
    final dests = _destinations(adultMode);
    final size = miraiWindowSizeOf(context);
    final useRail = size.isAtLeastMedium;

    final children = adultMode
        ? [
            AdultHomeScreen(
              repository: widget.documentRepository,
              ownerUid:
                  widget.authService.session?.uid ?? widget.assignedToUserId,
              authService: widget.authService,
              listeningStats: widget.listeningStatsRepository,
            ),
            DocumentsListScreen(
              repository: widget.documentRepository,
              ownerUid:
                  widget.authService.session?.uid ?? widget.assignedToUserId,
              authService: widget.authService,
            ),
            AdultToolsScreen(
              authService: widget.authService,
              documentRepository: widget.documentRepository,
              listeningStatsRepository: widget.listeningStatsRepository,
              statsUid:
                  widget.authService.session?.uid ?? widget.assignedToUserId,
            ),
          ]
        : [
            HomeTabScreen(
              repository: widget.homeworkRepository,
              deckRepository: widget.deckRepository,
              authService: widget.authService,
              xpRepository: widget.xpRepository,
              familyId: widget.familyId,
              assignedToUserId: widget.assignedToUserId,
              onOpenHomework: () => setState(() => _index = 1),
              onSignOut: widget.authService.signOut,
            ),
            HomeworkListScreen(
              repository: widget.homeworkRepository,
              deckRepository: widget.deckRepository,
              familyId: widget.familyId,
              assignedToUserId: widget.assignedToUserId,
              authService: widget.authService,
            ),
          ];

    final body = IndexedStack(index: shellIndex, children: children);

    if (useRail) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: shellIndex,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: size.isAtLeastExpanded
                    ? NavigationRailLabelType.all
                    : NavigationRailLabelType.selected,
                destinations: [
                  for (final d in dests)
                    NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(
                width: 1,
                color: MiraiTokens.borderSubtle,
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shellIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in dests)
            NavigationDestination(
              icon: d.icon,
              selectedIcon: d.selectedIcon,
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _ShellDest {
  const _ShellDest({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

/// Tredje fliken i vuxen-shell: statistik/verktyg; `both` växlar läge via Hem-flikens segment.
class AdultToolsScreen extends StatefulWidget {
  const AdultToolsScreen({
    super.key,
    required this.authService,
    required this.documentRepository,
    this.listeningStatsRepository,
    required this.statsUid,
  });

  final AuthService authService;
  final DocumentRepository documentRepository;
  final FirestoreListeningStatsRepository? listeningStatsRepository;
  final String statsUid;

  @override
  State<AdultToolsScreen> createState() => _AdultToolsScreenState();
}

class _AdultToolsScreenState extends State<AdultToolsScreen> {
  bool _savingPersona = false;
  bool _autoDeleteRecordingAudio = false;
  bool _autoDeleteLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAutoDeleteSetting();
  }

  Future<void> _loadAutoDeleteSetting() async {
    final v = await getAutoDeleteRecordingAudio();
    if (!mounted) return;
    setState(() {
      _autoDeleteRecordingAudio = v;
      _autoDeleteLoaded = true;
    });
  }

  Future<void> _setAutoDeleteRecordingAudio(bool value) async {
    setState(() => _autoDeleteRecordingAudio = value);
    await setAutoDeleteRecordingAudio(value);
  }

  Future<void> _upgradeToBoth() async {
    if (_savingPersona) return;
    setState(() => _savingPersona = true);
    try {
      await widget.authService.savePersona(UserPersona.both);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Klart! Du kan nu växla mellan barn- och vuxenläge.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att uppdatera läget. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _savingPersona = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final both = widget.authService.savedPersona == UserPersona.both;

    return Scaffold(
      body: SafeArea(
        child: MiraiContentPanel(
          child: ListView(
              padding: const EdgeInsets.all(MiraiTokens.spaceLg),
              children: [
                Text('Verktyg', style: tt.headlineLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w600)),
                const SizedBox(height: MiraiTokens.spaceXs),
                if (kUseFirestoreHomework &&
                    widget.listeningStatsRepository != null &&
                    widget.statsUid.isNotEmpty) ...[
                  ListeningStatsSection(
                    uid: widget.statsUid,
                    stats: widget.listeningStatsRepository!,
                    documentRepository: widget.documentRepository,
                  ),
                  const SizedBox(height: MiraiTokens.spaceLg),
                ],
                Card(
                  child: SwitchListTile(
                    value: MiraiTokens.lowStimuli,
                    onChanged: (v) => MiraiTokens.setLowStimuli(v),
                    title: const Text('Lågstimuli-läge'),
                    subtitle: const Text(
                      'Tonar ner dagsfärger, gradienter och skuggor — '
                      'för dagar då allt är för mycket.',
                    ),
                    secondary: const Icon(Icons.blur_on_rounded),
                  ),
                ),
                if (_autoDeleteLoaded) ...[
                  const SizedBox(height: MiraiTokens.spaceSm),
                  Card(
                    child: SwitchListTile(
                      value: _autoDeleteRecordingAudio,
                      onChanged: _setAutoDeleteRecordingAudio,
                      title: const Text('Radera ljudfilen efter transkription'),
                      subtitle: const Text(
                        'Sparar bara transkript och sammanfattning från inspelningar, '
                        'inte själva ljudet.',
                      ),
                      secondary: const Icon(Icons.mic_off_outlined),
                    ),
                  ),
                ],
                const SizedBox(height: MiraiTokens.spaceLg),
                Text(
                  both
                      ? 'Växla till barnläge med Barn/Vuxen högst upp på Hem för att hantera läxor och flashcards.'
                      : 'Du är i vuxenläge. Aktivera barn- och vuxenläge nedan för att kunna växla.',
                  style: tt.bodyMedium?.copyWith(color: MiraiTokens.textTertiary),
                ),
                const SizedBox(height: MiraiTokens.spaceLg),
                if (!both)
                  FilledButton.icon(
                    onPressed: _savingPersona ? null : _upgradeToBoth,
                    icon: const Icon(Icons.sync_alt_rounded),
                    label: Text(
                      _savingPersona
                          ? 'Aktiverar...'
                          : 'Aktivera barn- och vuxenläge',
                    ),
                  ),
              ],
            ),
        ),
      ),
    );
  }
}
