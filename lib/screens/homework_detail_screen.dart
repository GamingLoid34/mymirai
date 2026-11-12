import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../config.dart';
import '../data/local_homework_repository.dart';
import 'local_homework_lesson.dart';
import '../data/deck_repository.dart';
import '../data/dev_session_log_repository.dart';
import '../data/firestore_session_log_repository.dart';
import '../data/homework_repository.dart';
import '../data/session_log_repository.dart';
import '../data/xp_repository.dart';
import '../models/flashcard.dart';
import '../models/flashcard_deck.dart';
import '../models/homework_attachment.dart';
import '../models/homework_item.dart';
import '../models/math_problem_entry.dart';
import '../models/study_session_log.dart';
import 'flashcard_deck_screen.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/snap_pipeline_service.dart';
import '../services/spaced_repetition.dart';
import '../services/xp_rules.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../theme/subject_colors.dart';
import '../util/friendly_errors.dart';
import '../util/homework_listenable_text.dart';
import '../util/homework_steps.dart';
import '../util/merge_extracted_texts.dart';
import '../util/q_and_a_heuristic.dart';
import '../widgets/celebration.dart';
import '../widgets/premium_listening_sheet.dart';
import '../widgets/session_duration_picker.dart';
import '../widgets/tts_player_sheet.dart';
import '../widgets/vocabulary_edit_list.dart';
import '../widgets/xp_chip.dart';
import 'homework_edit_screen.dart';
import 'study_session_screen.dart';

class HomeworkDetailScreen extends StatefulWidget {
  const HomeworkDetailScreen({
    super.key,
    required this.repository,
    required this.familyId,
    required this.assignedToUserId,
    required this.homeworkId,
    this.deckRepository,
    this.autoPipeline = false,
    this.autoStartQuiz = false,
    this.authService,
    this.xpRepository,
  });

  final HomeworkRepository repository;
  final String familyId;
  final String assignedToUserId;
  final String homeworkId;

  /// `null` när appen inte använder Firestore-läge (flashcards inaktiverat).
  final DeckRepository? deckRepository;

  /// Styr barnförenklingar (`activePersona == UserPersona.child`). `null` = vuxenvy.
  final AuthService? authService;

  final XpRepository? xpRepository;

  /// Om `true` körs sammanfattning + flashcards/glosor/matte automatiskt när
  /// första data har laddats. Körs bara en gång per skärm.
  final bool autoPipeline;

  /// Om `true` startas förhör automatiskt så fort läxan laddats.
  final bool autoStartQuiz;

  @override
  State<HomeworkDetailScreen> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<HomeworkDetailScreen> {
  final _ai = AiService();
  bool _aiBusy = false;
  bool _hideQaSuggest = false;

  /// Så att inte [StreamBuilder] (item borta efter Firestore-delete) gör `pop()`
  /// i samma läge som [_deleteHomework] — dubbel-pop gav svart skärm.
  final bool _pendingLocalHomeworkDeletion = false;

  /// Flagga för att autoPipeline bara körs en gång.
  bool _autoPipelineRan = false;

  /// Flagga för att autoStartQuiz bara körs en gång.
  bool _autoStartQuizRan = false;

  /// Styr redigeringsläge för gloslistan (AP5).
  bool _editingVocabulary = false;

  /// Flagga för att steg-härledningen bara triggas en gång per skärm.
  bool _stepsEnsureRan = false;

  Future<void> _openEdit(HomeworkItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HomeworkEditScreen(
          repository: widget.repository,
          familyId: widget.familyId,
          assignedToUserId: widget.assignedToUserId,
          initial: item,
        ),
      ),
    );
  }

  Future<void> _deleteHomework(HomeworkItem item) async {
    final hasLinkedDeck = (item.linkedDeckId ?? '').trim().isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort läxan?'),
        content: Text(
          hasLinkedDeck
              ? 'Foton och allt du gjort med läxan försvinner. Flashcards till läxan finns kvar under Läxor → lekar.'
              : 'Foton och allt du gjort med läxan försvinner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MiraiTokens.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final backup = item;
    Navigator.of(context).pop(); // stänger bottomsheet
    await widget.repository.delete(item.id);
    if (!mounted) return;
    Navigator.of(context).pop(); // stänger detaljvyn
    MyMiraiApp.scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text('Läxan togs bort'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Ångra',
          onPressed: () async {
            await widget.repository.create(backup);
          },
        ),
      ),
    );
  }

  Future<void> _generateSummary(HomeworkItem item, {required bool overwrite}) async {
    final text = item.extractedText?.trim();
    if (text == null || text.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final summary = await _ai.summarize(text);
      await widget.repository.update(item.copyWith(summary: summary));
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att skapa sammanfattningen. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _openFlashcardsDeck(String deckId) async {
    final dr = widget.deckRepository;
    if (dr == null) return;
    final isChildMode = widget.authService?.activePersona == UserPersona.child;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FlashcardDeckScreen(
          deckRepository: dr,
          deckId: deckId,
          onStudyCompleted: () =>
              _bockStepByLabel('Träna korten', altLabel: 'Träna glosorna'),
          onQuizCompleted: () =>
              _bockStepByLabel('Förhör dig själv', altLabel: 'Gör förhöret'),
          xpRepository: widget.xpRepository,
          uid: widget.assignedToUserId,
          isChildMode: isChildMode,
        ),
      ),
    );
  }

  Future<void> _bockStepByLabel(String label, {String? altLabel}) async {
    final snapList = await widget.repository
        .watchForFamily(
          familyId: widget.familyId,
          assignedToUserId: widget.assignedToUserId,
        )
        .first;
    HomeworkItem? current;
    for (final h in snapList) {
      if (h.id == widget.homeworkId) current = h;
    }
    if (current == null) return;
    HomeworkStep? step;
    for (final s in current.steps) {
      if (s.label == label || (altLabel != null && s.label == altLabel)) step = s;
    }
    if (step == null) return;
    await _setStepDone(current, step.id, true);
  }

  Future<HomeworkItem> _ensureVocabularyParsed(HomeworkItem item) async {
    final extracted = (item.extractedText ?? '').trim();
    if (item.vocabulary.isNotEmpty || extracted.isEmpty) {
      return item;
    }
    try {
      final entries = await _ai.parseVocabulary(rawText: extracted);
      final updated = item.copyWith(vocabulary: entries);
      await widget.repository.update(updated);
      return updated;
    } catch (e) {
      if (mounted) {
        showFriendlySnack(
          context,
          'Hoppsan – det gick inte att tolka glosorna. Testa igen om en stund.',
          error: e,
        );
      }
      return item;
    }
  }

  Future<String?> _ensureVocabularyDeck(HomeworkItem current) async {
    if (widget.deckRepository == null) return null;
    final existingDeckId = (current.linkedDeckId ?? '').trim();
    if (existingDeckId.isNotEmpty) {
      return existingDeckId;
    }
    if (!current.isVocabularyHomework || current.vocabulary.isEmpty) return null;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Skapar gloskort…')),
          ],
        ),
      ),
    );
    try {
      final r = await _ai.generateVocabularyFlashcards(current.id);
      if (!mounted) return null;
      Navigator.of(context).pop();
      return r.deckId;
    } catch (e) {
      if (!mounted) return null;
      Navigator.of(context).pop();
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att skapa gloskorten. Testa igen om en stund.',
        error: e,
      );
      return null;
    }
  }

  Future<void> _generateVocabularyFlashcards(HomeworkItem current) async {
    final deckId = await _ensureVocabularyDeck(current);
    if (deckId == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Glos-kort skapades')),
    );
    await _openFlashcardsDeck(deckId);
  }

  Future<void> _startVocabularyQuiz(HomeworkItem current) async {
    if (widget.deckRepository == null) return;
    var item = current;
    final extracted = (item.extractedText ?? '').trim();
    if (item.vocabulary.isEmpty && extracted.isNotEmpty) {
      item = await _ensureVocabularyParsed(item);
    }
    if (item.vocabulary.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inga glosor att förhöra på än.')),
        );
      }
      return;
    }
    final deckId = await _ensureVocabularyDeck(item);
    if (deckId == null || !mounted) return;

    final isChildMode = widget.authService?.activePersona == UserPersona.child;
    int? minutes;
    if (isChildMode) {
      minutes = await showSessionDurationPicker(context);
      if (!mounted) return;
    }

    final cards = await widget.deckRepository!.watchCardsInDeck(deckId).first;
    if (!mounted) return;
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inga kort i leken än.')),
      );
      return;
    }

    final shuffled = List.of(cards)..shuffle();
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StudySessionScreen(
          deckRepository: widget.deckRepository!,
          deck: null,
          cards: shuffled,
          xpRepository: widget.xpRepository,
          uid: widget.assignedToUserId,
          sessionDurationMinutes: minutes,
          simplifiedRating: true,
          homeworkId: current.id,
        ),
      ),
    );

    if (done == true) {
      await _bockStepByLabel('Förhör dig själv', altLabel: 'Gör förhöret');
    }
  }

  Future<void> _startStudy(HomeworkItem current) async {
    if (widget.deckRepository == null) return;
    var item = current;
    if (item.isVocabularyHomework) {
      final extracted = (item.extractedText ?? '').trim();
      if (item.vocabulary.isEmpty && extracted.isNotEmpty) {
        item = await _ensureVocabularyParsed(item);
      }
    }
    String? deckId = (item.linkedDeckId ?? '').trim();
    if (deckId.isEmpty && item.isVocabularyHomework) {
      deckId = await _ensureVocabularyDeck(item);
    }
    if (deckId == null || deckId.isEmpty || !mounted) return;

    final isChildMode = widget.authService?.activePersona == UserPersona.child;
    int? minutes;
    if (isChildMode) {
      minutes = await showSessionDurationPicker(context);
      if (!mounted) return;
    }

    final cards = await widget.deckRepository!.watchCardsInDeck(deckId).first;
    if (!mounted) return;
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inga kort att repetera än.')),
      );
      return;
    }
    final dueCards = SpacedRepetition.sortForStudy(cards, DateTime.now());
    final cardsToStudy = dueCards.isNotEmpty ? dueCards : cards;

    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StudySessionScreen(
          deckRepository: widget.deckRepository!,
          deck: null,
          cards: cardsToStudy,
          xpRepository: widget.xpRepository,
          uid: widget.assignedToUserId,
          sessionDurationMinutes: minutes,
          homeworkId: item.id,
        ),
      ),
    );

    if (done == true) {
      await _bockStepByLabel('Träna korten', altLabel: 'Träna glosorna');
    }
  }

  Future<void> _startTextQuiz(HomeworkItem current) async {
    final deckId = (current.linkedDeckId ?? '').trim();
    if (deckId.isEmpty || widget.deckRepository == null) return;

    final isChildMode = widget.authService?.activePersona == UserPersona.child;
    int? minutes;
    if (isChildMode) {
      minutes = await showSessionDurationPicker(context);
      if (!mounted) return;
    }

    final cards = await widget.deckRepository!.watchCardsInDeck(deckId).first;
    if (!mounted || cards.isEmpty) return;

    final shuffled = List.of(cards)..shuffle();
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StudySessionScreen(
          deckRepository: widget.deckRepository!,
          deck: null,
          cards: shuffled,
          xpRepository: widget.xpRepository,
          uid: widget.assignedToUserId,
          sessionDurationMinutes: minutes,
          simplifiedRating: true,
          homeworkId: current.id,
        ),
      ),
    );

    if (done == true) {
      await _bockStepByLabel('Förhör dig själv', altLabel: 'Gör förhöret');
    }
  }

  Future<void> _generateFlashcards(HomeworkItem current) async {
    if (widget.deckRepository == null) return;
    final hasSummary = (current.summary ?? '').trim().isNotEmpty;
    if (!hasSummary) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text('Skapar flashcards…'),
            ),
          ],
        ),
      ),
    );
    try {
      final result = await _ai.generateFlashcards(current.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.cards.length} kort skapade')),
      );
      await _openFlashcardsDeck(result.deckId);
    } on AiNoSummaryException catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generera först en sammanfattning av läxan'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att skapa flashcards. Testa igen om en stund.',
        error: e,
      );
    }
  }

  Future<void> _deleteLinkedDeck(HomeworkItem current, String deckId) async {
    if (widget.deckRepository == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort flashcards?'),
        content: const Text(
          'Alla kort i leken tas bort. Det går inte att ångra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.deckRepository!.deleteDeck(deckId);
      await widget.repository.update(
        current.copyWith(linkedDeckId: ''),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flashcards togs bort')),
      );
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att ta bort. Testa igen om en stund.',
        error: e,
      );
    }
  }

  Future<void> _parseMathProblemsFromText(HomeworkItem item) async {
    final t = item.extractedText?.trim() ?? '';
    if (t.length < 10) return;
    setState(() => _aiBusy = true);
    try {
      final list = await _ai.parseMathProblems(t);
      await widget.repository.update(item.copyWith(mathProblems: list));
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att hitta uppgifterna. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _explainMathProblem(HomeworkItem item, int index) async {
    if (index < 0 || index >= item.mathProblems.length) return;
    final p = item.mathProblems[index];
    setState(() => _aiBusy = true);
    try {
      final expl = await _ai.explainMathStep(p.originalText);
      final next = List<MathProblemEntry>.from(item.mathProblems);
      next[index] = p.copyWith(explanation: expl);
      await widget.repository.update(item.copyWith(mathProblems: next));
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att ta fram en förklaring. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _varyMathProblem(HomeworkItem item, int index) async {
    if (index < 0 || index >= item.mathProblems.length) return;
    final p = item.mathProblems[index];
    setState(() => _aiBusy = true);
    try {
      final vars = await _ai.varyMathProblem(
        p.originalText,
        homeworkId: item.id,
        gradeHint: item.gradeHint,
      );
      final next = List<MathProblemEntry>.from(item.mathProblems);
      next[index] = p.copyWith(variants: vars);
      await widget.repository.update(item.copyWith(mathProblems: next));
    } on AiInvalidInputException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att variera uppgiften. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _extractAttachment(HomeworkItem item) async {
    final rows = attachmentsOrLegacySynthetic(item);
    if (rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Läxan har ingen bilaga att läsa.')),
      );
      return;
    }

    var attachmentIndex = 0;
    if (rows.length > 1) {
      if (!mounted) return;
      final picked = await showModalBottomSheet<int>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows.length; i++)
                ListTile(
                  title: Text(
                    rows[i].fileName.trim().isEmpty
                        ? 'Bilaga ${i + 1}'
                        : rows[i].fileName,
                  ),
                  onTap: () => Navigator.of(ctx).pop(i),
                ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      attachmentIndex = picked;
    }

    await _extractAttachmentAt(item, attachmentIndex);
  }

  Future<void> _extractAttachmentAt(HomeworkItem item, int attachmentIndex) async {
    setState(() => _aiBusy = true);
    try {
      final result = await _ai.extractFromAttachment(
        item.id,
        attachmentIndex: attachmentIndex,
      );
      if (result.text.isEmpty && result.warning == 'no_text_layer') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF:en saknar textlager. Ta ett foto av sidan istället.'),
          ),
        );
        return;
      }
      await widget.repository.update(
        withAttachmentExtractApplied(item, attachmentIndex, result.text),
      );
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att extrahera texten. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _parseQuestionsFromMaterial(HomeworkItem current) async {
    if (widget.deckRepository == null) return;
    final ext = current.extractedText?.trim() ?? '';
    if (ext.isEmpty) return;
    if (!kUseFirestoreHomework || current.id.startsWith('dev-')) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Hittar frågor i materialet…')),
          ],
        ),
      ),
    );
    try {
      final deckId = await _ai.parseQuestionsAndAnswers(homeworkId: current.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lek skapad från materialet')),
      );
      await _openFlashcardsDeck(deckId);
    } on AiInvalidInputException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on AiUnavailableException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att skapa leken. Testa igen om en stund.',
        error: e,
      );
    }
  }

  Future<void> _useExtractedAsSummary(HomeworkItem current) async {
    final ext = current.extractedText?.trim() ?? '';
    if (ext.isEmpty) return;

    Future<void> go() async {
      setState(() => _aiBusy = true);
      try {
        await widget.repository.update(current.copyWith(summary: ext));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sammanfattning satt från materialet.')),
        );
      } finally {
        if (mounted) setState(() => _aiBusy = false);
      }
    }

    if (ext.length > 4000) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lång text'),
          content: Text(
            'Texten är ganska lång (${ext.length} tecken) — säker på att du vill '
            'använda den som sammanfattning utan att korta ner?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ja, använd hela'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) await go();
      return;
    }
    await go();
  }

  Future<void> _setStepDone(HomeworkItem item, String stepId, bool done) async {
    HomeworkStep? target;
    for (final s in item.steps) {
      if (s.id == stepId) target = s;
    }
    if (target == null || target.done == done) return;
    final updated = [
      for (final s in item.steps) s.id == stepId ? s.copyWith(done: done) : s,
    ];
    if (!kIsWeb) await HapticFeedback.selectionClick();
    await widget.repository.update(item.copyWith(steps: updated));
  }

  void _bockListenStep(HomeworkItem item) {
    HomeworkStep? listenStep;
    for (final s in item.steps) {
      if (s.label == 'Lyssna på läxan' || s.label == 'Lyssna på orden') {
        listenStep = s;
      }
    }
    if (listenStep == null || listenStep.done) return;
    _setStepDone(item, listenStep.id, true);
    _awardXp(XpRules.listeningDone);
  }

  void _ensureStepsGenerated(HomeworkItem item) {
    if (_stepsEnsureRan || item.steps.isNotEmpty) return;
    _stepsEnsureRan = true;
    final derived = deriveSteps(item);
    if (derived.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await widget.repository.update(item.copyWith(steps: derived));
    });
  }

  void _triggerAutoPipeline(HomeworkItem item) {
    if (!widget.autoPipeline || _autoPipelineRan) return;
    if (!kUseFirestoreHomework || item.id.startsWith('dev-')) return;
    _autoPipelineRan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _runAutoPipeline(item);
    });
  }

  void _triggerAutoStartQuiz(HomeworkItem item) {
    if (!widget.autoStartQuiz || _autoStartQuizRan) return;
    _autoStartQuizRan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _startVocabularyQuiz(item);
    });
  }

  Future<void> _runAutoPipeline(HomeworkItem item) async {
    final extracted = (item.extractedText ?? '').trim();
    final type = item.homeworkType;

    if (type == 'vocabulary') {
      if (item.vocabulary.isEmpty && extracted.isNotEmpty) {
        try {
          final entries = await _ai.parseVocabulary(rawText: extracted);
          final updated = item.copyWith(vocabulary: entries);
          await widget.repository.update(updated);
          if (!mounted) return;
          if (widget.autoStartQuiz) {
            final fresh = updated;
            await _generateVocabularyFlashcards(fresh);
          }
        } catch (e) {
          if (!mounted) return;
          showFriendlySnack(
            context,
            'Hoppsan – det gick inte att tolka glosorna. Testa igen om en stund.',
            error: e,
          );
        }
      }
      return;
    }

    if (type == 'math') {
      if (item.mathProblems.isEmpty && extracted.length >= 10) {
        await _parseMathProblemsFromText(item);
      }
      return;
    }

    // type == 'text' (default)
    if (extracted.isNotEmpty) {
      if ((item.summary ?? '').trim().isEmpty) {
        await _generateSummary(item, overwrite: false);
        if (!mounted) return;
      }
      // Läs aktuell snapshot för att se om summary skapades
      if (widget.deckRepository != null) {
        final snapList = await widget.repository
            .watchForFamily(
              familyId: widget.familyId,
              assignedToUserId: widget.assignedToUserId,
            )
            .first;
        HomeworkItem? fresh;
        for (final h in snapList) {
          if (h.id == item.id) {
            fresh = h;
            break;
          }
        }
        if (fresh != null &&
            (fresh.summary ?? '').trim().isNotEmpty &&
            (fresh.linkedDeckId ?? '').trim().isEmpty) {
          await _generateFlashcards(fresh);
        }
      }
    }
  }

  Future<void> _toggleDone(HomeworkItem item) async {
    final wasDone = item.status == HomeworkStatus.done;
    if (!kIsWeb) await HapticFeedback.lightImpact();
    final next = wasDone ? HomeworkStatus.inProgress : HomeworkStatus.done;
    await widget.repository.update(item.copyWith(status: next));
    if (!wasDone && mounted) {
      Celebration.show(context, size: CelebrationSize.large);
      _awardXp(XpRules.homeworkDone);
    }
  }

  void _awardXp(int amount) {
    final xp = widget.xpRepository;
    final uid = widget.assignedToUserId;
    if (xp == null) return;
    xp.addXp(uid, amount);
    if (mounted) XpChip.show(context, amount);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return StreamBuilder<List<HomeworkItem>>(
      stream: widget.repository.watchForFamily(
        familyId: widget.familyId,
        assignedToUserId: widget.assignedToUserId,
      ),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data!;
        HomeworkItem? item;
        for (final h in items) {
          if (h.id == widget.homeworkId) item = h;
        }
        if (item == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Lokalt initiierad delete: [_deleteHomework] stänger redan rutten.
            if (_pendingLocalHomeworkDeletion) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Läxan finns inte längre')),
            );
            Navigator.of(context).maybePop();
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final repository = widget.repository;
        if (repository is LocalHomeworkRepository) {
          return LocalHomeworkLesson(key: ValueKey(item.id), item: item, repository: repository);
        }

        _triggerAutoPipeline(item);
        _triggerAutoStartQuiz(item);
        _ensureStepsGenerated(item);

        final isChildMode =
            widget.authService?.activePersona == UserPersona.child;
        if (isChildMode) {
          return _ChildDetailBody(
            item: item,
            repository: widget.repository,
            deckRepository: widget.deckRepository,
            onOpenFlashcardsDeck: _openFlashcardsDeck,
            onToggleDone: _toggleDone,
            onSetStepDone: _setStepDone,
            onListen: (current, onFinished) {
              final text = listenableHomeworkText(current)?.trim();
              if (text == null || text.isEmpty) return;
              showTtsPlayer(
                context,
                text: text,
                title: current.title,
                subject: current.subject,
                onFinished: () {
                  _bockListenStep(current);
                  onFinished();
                },
              );
            },
            onStartStudy: _startStudy,
            onStartQuiz: (c) => c.isVocabularyHomework
                ? _startVocabularyQuiz(c)
                : _startTextQuiz(c),
          );
        }

        final listenable = listenableHomeworkText(item);
        final summary = item.summary?.trim();
        final extracted = item.extractedText?.trim();
        final current = item;
        final attachmentSources = attachmentsOrLegacySynthetic(current);
        final isLocalOnlyDemo = kUseFirestoreHomework && current.id.startsWith('dev-');

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              _TopCircleButton(
                icon: Icons.edit_outlined,
                onTap: () => _openEdit(current),
              ),
              const SizedBox(width: 8),
              _TopCircleButton(
                icon: Icons.more_horiz_rounded,
                onTap: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline_rounded, color: MiraiTokens.danger),
                        title: const Text('Ta bort läxa'),
                        textColor: MiraiTokens.danger,
                        iconColor: MiraiTokens.danger,
                        onTap: () => _deleteHomework(current),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: MiraiTokens.bgBase,
              border: Border(top: BorderSide(color: MiraiTokens.borderSubtle)),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: MiraiTokens.spaceLg,
              vertical: MiraiTokens.spaceSm,
            ),
            child: SafeArea(
              top: false,
              child: current.status == HomeworkStatus.done
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Klar ✓',
                          style: tt.titleMedium?.copyWith(
                            color: MiraiTokens.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: MiraiTokens.spaceSm),
                        TextButton(
                          onPressed: () => _toggleDone(current),
                          child: const Text('Ångra'),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _toggleDone(current),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Klart med läxan! 🎉'),
                      ),
                    ),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: MiraiAdaptiveBox(
                child: ListView(
                  padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                  children: [
                    _PipelineStatusBanner(homeworkId: current.id),
                    if (isLocalOnlyDemo) ...[
                      Container(
                        padding: const EdgeInsets.all(MiraiTokens.spaceSm),
                        decoration: BoxDecoration(
                          color: MiraiTokens.bgRaised,
                          borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                          border: Border.all(color: MiraiTokens.warning, width: MiraiTokens.borderThin),
                        ),
                        child: Text(
                          'Den här läxan finns bara lokalt (gammal demo-data). Skapa en ny.',
                          style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
                        ),
                      ),
                      const SizedBox(height: MiraiTokens.spaceMd),
                    ],
                    if (current.subject.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: MiraiTokens.bgInteractive,
                          borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
                          border: Border.all(
                            color: subjectAccentColor(current.subject)
                                .withValues(alpha: 0.45),
                            width: MiraiTokens.borderThin,
                          ),
                        ),
                        child: Text(
                          current.subject.toUpperCase(),
                          style: tt.labelSmall?.copyWith(
                            letterSpacing: 0.5,
                            color: MiraiTokens.textSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: MiraiTokens.spaceSm),
                    Text(
                      current.title,
                      style: tt.headlineMedium?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _detailMeta(current),
                      style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                    ),
                    const SizedBox(height: MiraiTokens.spaceLg),
                    if (current.isVocabularyHomework) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _startVocabularyQuiz(current),
                          icon: const Icon(Icons.quiz_rounded),
                          label: const Text('Starta förhör'),
                        ),
                      ),
                      const SizedBox(height: MiraiTokens.spaceSm),
                    ],
                    Tooltip(
                      message: listenable == null
                          ? 'Lägg till text eller sammanfattning först'
                          : 'Lyssna',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (current.isVocabularyHomework)
                            OutlinedButton.icon(
                              onPressed: listenable == null
                                  ? null
                                  : () {
                                      final text = listenable.trim();
                                      if (text.isEmpty) return;
                                      showTtsPlayer(
                                        context,
                                        text: text,
                                        title: current.title,
                                        subject: current.subject,
                                        onFinished: () => _bockListenStep(current),
                                      );
                                    },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                listenable == null
                                    ? 'Inget att lyssna på än'
                                    : listenableHomeworkLabel(current),
                              ),
                            )
                          else
                            FilledButton.icon(
                              onPressed: listenable == null
                                  ? null
                                  : () {
                                      final text = listenable.trim();
                                      if (text.isEmpty) return;
                                      showTtsPlayer(
                                        context,
                                        text: text,
                                        title: current.title,
                                        subject: current.subject,
                                        onFinished: () => _bockListenStep(current),
                                      );
                                    },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                listenable == null
                                    ? 'Inget att lyssna på än'
                                    : listenableHomeworkLabel(current),
                              ),
                            ),
                          if (listenable != null) ...[
                            const SizedBox(height: MiraiTokens.spaceSm),
                            OutlinedButton.icon(
                              onPressed: () => showPremiumListeningSheet(
                                context,
                                titleHint: current.title,
                                load: () => _ai.listeningStory(
                                      homeworkId: current.id,
                                    ),
                              ),
                              icon: const Icon(Icons.cloud_rounded),
                              label: const Text('Saga med molnröst'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: MiraiTokens.spaceLg),
                    if (attachmentSources.isNotEmpty) ...[
                      _SourcesPanel(
                        attachments: attachmentSources,
                        aiBusy: _aiBusy,
                        isLocalOnlyDemo: isLocalOnlyDemo,
                        onChangeRole: (i, role) async {
                          final next = [...attachmentSources];
                          if (i < 0 || i >= next.length) return;
                          next[i] = next[i].copyWith(role: role);
                          await widget.repository.update(
                            current.copyWith(attachments: next),
                          );
                        },
                        onExtractAt: (i) =>
                            _extractAttachmentAt(current, i),
                      ),
                      const SizedBox(height: MiraiTokens.spaceLg),
                    ],
                    if (current.isVocabularyHomework &&
                        (current.vocabulary.isNotEmpty || _editingVocabulary)) ...[
                      Row(
                        children: [
                          Text(
                            'GLOSOR',
                            style: tt.labelSmall?.copyWith(
                              letterSpacing: 0.5,
                              color: MiraiTokens.textTertiary,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setState(
                              () => _editingVocabulary = !_editingVocabulary,
                            ),
                            icon: Icon(
                              _editingVocabulary
                                  ? Icons.close_rounded
                                  : Icons.edit_outlined,
                              size: 16,
                            ),
                            label: Text(
                              _editingVocabulary ? 'Avbryt' : 'Rätta glosor',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: MiraiTokens.spaceSm),
                      if (_editingVocabulary)
                        VocabularyEditList(
                          initialEntries: current.vocabulary,
                          onCancel: () =>
                              setState(() => _editingVocabulary = false),
                          onSaved: (edited) async {
                            setState(() => _editingVocabulary = false);
                            final updated =
                                current.copyWith(vocabulary: edited);
                            await widget.repository.update(updated);
                            if (!context.mounted) return;
                            if ((current.linkedDeckId ?? '').trim().isNotEmpty) {
                              final updateDeck = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Uppdatera förhörskorten?'),
                                  content: const Text(
                                    'Vill du uppdatera förhörskorten med de rättade glosorna?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('Nej'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: const Text('Ja, uppdatera'),
                                    ),
                                  ],
                                ),
                              );
                              if (updateDeck == true && mounted) {
                                await _generateVocabularyFlashcards(updated);
                              }
                            }
                          },
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: MiraiTokens.bgRaised,
                            borderRadius:
                                BorderRadius.circular(MiraiTokens.radiusMd),
                            border: Border.all(
                              color: MiraiTokens.borderSubtle,
                              width: MiraiTokens.borderThin,
                            ),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: current.vocabulary.length,
                            separatorBuilder: (_, index) => const Divider(
                              height: 1,
                              color: MiraiTokens.borderSubtle,
                            ),
                            itemBuilder: (ctx, i) {
                              final e = current.vocabulary[i];
                              return ListTile(
                                dense: true,
                                title: Text(e.term, style: tt.bodyMedium),
                                subtitle: Text(
                                  [
                                    e.translation,
                                    if ((e.example ?? '').trim().isNotEmpty)
                                      '“${e.example}”',
                                  ].join('\n'),
                                  style: tt.bodySmall,
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: MiraiTokens.spaceMd),
                    ],
                    if (!current.isVocabularyHomework) ...[
                      Text(
                        'SAMMANFATTNING',
                        style: tt.labelSmall?.copyWith(
                          letterSpacing: 0.5,
                          color: MiraiTokens.textTertiary,
                        ),
                      ),
                      const SizedBox(height: MiraiTokens.spaceSm),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: MiraiTokens.bgRaised,
                          borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                          border: Border.all(
                            color: MiraiTokens.borderSubtle,
                            width: MiraiTokens.borderThin,
                          ),
                        ),
                        child: () {
                          Widget? qaExtractLink() {
                            if (extracted == null || extracted.isEmpty) return null;
                            if (looksLikeQAndA(extracted)) return null;
                            if (_aiBusy ||
                                isLocalOnlyDemo ||
                                !kUseFirestoreHomework ||
                                widget.deckRepository == null) {
                              return null;
                            }
                            return TextButton(
                              onPressed: () => _parseQuestionsFromMaterial(current),
                              child: const Text(
                                'Innehåller materialet redan frågor med svar? Extrahera dem.',
                              ),
                            );
                          }
                          if (summary != null && summary.isNotEmpty) {
                            final link = qaExtractLink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  summary,
                                  style: tt.bodyMedium?.copyWith(height: 1.55),
                                ),
                                if (link != null) ...[
                                  const SizedBox(height: MiraiTokens.spaceSm),
                                  link,
                                ],
                              ],
                            );
                          }
                          if (extracted != null && extracted.isNotEmpty) {
                            final link = qaExtractLink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ingen sammanfattning än.',
                                  style: tt.bodyMedium?.copyWith(
                                    color: MiraiTokens.textSecondary,
                                  ),
                                ),
                                TextButton(
                                  onPressed: (_aiBusy || isLocalOnlyDemo)
                                      ? null
                                      : () => _generateSummary(current, overwrite: true),
                                  child: _aiBusy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Generera från text'),
                                ),
                                const SizedBox(height: MiraiTokens.spaceSm),
                                OutlinedButton(
                                  onPressed: (_aiBusy || isLocalOnlyDemo)
                                      ? null
                                      : () => _useExtractedAsSummary(current),
                                  child: const Text(
                                    'Använd texten som den är (hoppa över AI)',
                                  ),
                                ),
                                if (link != null) ...[
                                  const SizedBox(height: MiraiTokens.spaceXs),
                                  link,
                                ],
                              ],
                            );
                          }
                          return Text(
                            'Ladda upp material eller skriv text för att börja.',
                            style: tt.bodyMedium?.copyWith(color: MiraiTokens.textTertiary),
                          );
                        }(),
                      ),
                      const SizedBox(height: MiraiTokens.spaceMd),
                    ],
                    if (current.isMathHomework) ...[
                      Text(
                        'MATTEUPPGIFTER',
                        style: tt.labelSmall?.copyWith(
                          letterSpacing: 0.5,
                          color: MiraiTokens.textTertiary,
                        ),
                      ),
                      const SizedBox(height: MiraiTokens.spaceSm),
                      if (current.mathProblems.isEmpty &&
                          (extracted ?? '').length >= 10)
                        Padding(
                          padding: const EdgeInsets.only(bottom: MiraiTokens.spaceSm),
                          child: OutlinedButton.icon(
                            onPressed: (_aiBusy || isLocalOnlyDemo)
                                ? null
                                : () => _parseMathProblemsFromText(current),
                            icon: const Icon(Icons.functions_rounded, size: 18),
                            label: const Text('Hitta uppgifter i texten'),
                          ),
                        ),
                      if (current.mathProblems.isEmpty &&
                          (extracted ?? '').length < 10)
                        Text(
                          'Ingen text från stencil än. Ladda upp en tydlig bild eller vänta på OCR.',
                          style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                        ),
                      for (var i = 0; i < current.mathProblems.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: MiraiTokens.spaceSm),
                          child: _MathProblemPanel(
                            entry: current.mathProblems[i],
                            index: i,
                            aiBusy: _aiBusy,
                            varyBlocked: current.gradeHint != null &&
                                current.gradeHint! >= 7,
                            onExplain: () => _explainMathProblem(current, i),
                            onVary: () => _varyMathProblem(current, i),
                          ),
                        ),
                      const SizedBox(height: MiraiTokens.spaceMd),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ToolChip(
                          icon: Icons.edit_outlined,
                          label: 'Redigera',
                          onTap: () => _openEdit(current),
                        ),
                        if ((summary ?? '').isNotEmpty && (extracted ?? '').isNotEmpty)
                          (isLocalOnlyDemo
                              ? Tooltip(
                                  message: 'Den här läxan är inte sparad i molnet',
                                  child: _ToolChip(
                                    icon: Icons.auto_awesome,
                                    label: 'Ny sammanfattning',
                                    onTap: null,
                                  ),
                                )
                              : _ToolChip(
                                  icon: Icons.auto_awesome,
                                  label: 'Ny sammanfattning',
                                  onTap: _aiBusy ? null : () => _generateSummary(current, overwrite: true),
                                )),
                        if ((extracted ?? '').isNotEmpty)
                          _ToolChip(
                            icon: Icons.article_outlined,
                            label: 'Visa text',
                            onTap: () {
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (ctx) => FractionallySizedBox(
                                  heightFactor: 0.7,
                                  child: Padding(
                                    padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                                    child: SingleChildScrollView(
                                      child: Text(
                                        extracted!,
                                        style: tt.bodyMedium?.copyWith(height: 1.55),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        if (attachmentSources.isNotEmpty && (extracted ?? '').isEmpty)
                          (isLocalOnlyDemo
                              ? Tooltip(
                                  message: 'Den här läxan är inte sparad i molnet',
                                  child: _ToolChip(
                                    icon: Icons.text_snippet_outlined,
                                    label: 'Extrahera från bilaga',
                                    onTap: null,
                                  ),
                                )
                              : _ToolChip(
                                  icon: Icons.text_snippet_outlined,
                                  label: 'Extrahera från bilaga',
                                  onTap: _aiBusy ? null : () => _extractAttachment(current),
                                )),
                      ],
                    ),
                    if (widget.deckRepository != null &&
                        (!current.isMathHomework || current.isVocabularyHomework)) ...[
                      const SizedBox(height: MiraiTokens.spaceMd),
                      _FlashcardsHomeworkBanner(
                        current: current,
                        summaryTrimmed: summary,
                        deckRepository: widget.deckRepository!,
                        isLocalOnlyDemo: isLocalOnlyDemo,
                        aiBusy: _aiBusy,
                        hideQaSuggest: _hideQaSuggest,
                        onDismissQaSuggest: () =>
                            setState(() => _hideQaSuggest = true),
                        onParseQuestionsFromMaterial: () =>
                            _parseQuestionsFromMaterial(current),
                        onTapGenerate: () => _generateFlashcards(current),
                        onTapGenerateVocabulary: () =>
                            _generateVocabularyFlashcards(current),
                        onOpenDeck: _openFlashcardsDeck,
                        onDeleteDeck: (deckId) => _deleteLinkedDeck(current, deckId),
                      ),
                    ],
                    const SizedBox(height: MiraiTokens.space2xl),
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

/// Barnens lugna läxkort: EN checklista, EN stor primärknapp åt gången.
class _ChildDetailBody extends StatelessWidget {
  const _ChildDetailBody({
    required this.item,
    required this.repository,
    required this.deckRepository,
    required this.onOpenFlashcardsDeck,
    required this.onToggleDone,
    required this.onSetStepDone,
    required this.onListen,
    required this.onStartStudy,
    required this.onStartQuiz,
  });

  final HomeworkItem item;
  final HomeworkRepository repository;
  final DeckRepository? deckRepository;
  final Future<void> Function(String deckId) onOpenFlashcardsDeck;
  final Future<void> Function(HomeworkItem item) onToggleDone;
  final Future<void> Function(HomeworkItem item, String stepId, bool done) onSetStepDone;
  final void Function(HomeworkItem item, VoidCallback onFinished) onListen;
  final Future<void> Function(HomeworkItem item) onStartStudy;
  final Future<void> Function(HomeworkItem item) onStartQuiz;

  HomeworkStep? get _firstUndoneStep {
    for (final s in item.steps) {
      if (!s.done) return s;
    }
    return null;
  }

  ({String label, VoidCallback? onTap}) _primaryAction(BuildContext context) {
    final step = _firstUndoneStep;
    if (step == null) {
      return (label: '', onTap: null);
    }
    switch (step.label) {
      case 'Lyssna på läxan':
      case 'Lyssna på orden':
        return (
          label: 'Lyssna',
          onTap: () => onListen(item, () {}),
        );
      case 'Träna korten':
      case 'Träna glosorna':
        return (
          label: step.label,
          onTap: () => onStartStudy(item),
        );
      case 'Förhör dig själv':
      case 'Gör förhöret':
        return (
          label: step.label == 'Förhör dig själv'
              ? 'Förhör dig själv'
              : 'Gör förhöret',
          onTap: () => onStartQuiz(item),
        );
      default:
        return (
          label: step.label,
          onTap: () => onSetStepDone(item, step.id, true),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final summary = (item.summary ?? '').trim();
    final action = _primaryAction(context);
    final hasListenStep = item.steps.any(
      (s) => (s.label == 'Lyssna på läxan' || s.label == 'Lyssna på orden') && s.done,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: MiraiTokens.bgBase,
          border: Border(top: BorderSide(color: MiraiTokens.borderSubtle)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: MiraiTokens.spaceLg,
          vertical: MiraiTokens.spaceSm,
        ),
        child: SafeArea(
          top: false,
          child: item.status == HomeworkStatus.done
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Klar ✓',
                      style: tt.titleMedium?.copyWith(
                        color: MiraiTokens.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: MiraiTokens.spaceSm),
                    TextButton(
                      onPressed: () => onToggleDone(item),
                      child: const Text('Ångra'),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => onToggleDone(item),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Klart med läxan! 🎉'),
                  ),
                ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: MiraiAdaptiveBox(
            child: ListView(
              padding: const EdgeInsets.all(MiraiTokens.spaceLg),
              children: [
                _PipelineStatusBanner(homeworkId: item.id),
                if (item.subject.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: MiraiTokens.bgInteractive,
                      borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
                      border: Border.all(
                        color: subjectAccentColor(item.subject).withValues(alpha: 0.45),
                        width: MiraiTokens.borderThin,
                      ),
                    ),
                    child: Text(
                      _capitalize(item.subject.trim()),
                      style: tt.labelSmall?.copyWith(color: MiraiTokens.textSecondary),
                    ),
                  ),
                const SizedBox(height: MiraiTokens.spaceMd),
                Text(
                  item.title,
                  style: tt.headlineMedium?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _detailMeta(item),
                  style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: MiraiTokens.spaceMd),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(
                        'Vad handlar läxan om?',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: MiraiTokens.bgRaised,
                            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                            border: Border.all(
                              color: MiraiTokens.borderSubtle,
                              width: MiraiTokens.borderThin,
                            ),
                          ),
                          child: Text(
                            summary,
                            style: tt.bodyMedium?.copyWith(height: 1.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (item.steps.isNotEmpty) ...[
                  const SizedBox(height: MiraiTokens.spaceLg),
                  ...item.steps.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: MiraiTokens.spaceXs),
                      child: _StepRow(
                        step: s,
                        onTap: () => onSetStepDone(item, s.id, !s.done),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: MiraiTokens.spaceLg),
                if (action.onTap != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: action.onTap,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(action.label),
                    ),
                  ),
                if (hasListenStep) ...[
                  const SizedBox(height: MiraiTokens.spaceSm),
                  Center(
                    child: TextButton(
                      onPressed: () => onListen(item, () {}),
                      child: const Text('Lyssna igen'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.onTap});

  final HomeworkStep step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: MiraiTokens.bgRaised,
      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MiraiTokens.spaceMd,
            vertical: MiraiTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            border: Border.all(
              color: MiraiTokens.borderSubtle,
              width: MiraiTokens.borderThin,
            ),
          ),
          child: Row(
            children: [
              Icon(
                step.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: step.done ? MiraiTokens.success : MiraiTokens.textTertiary,
              ),
              const SizedBox(width: MiraiTokens.spaceSm),
              Expanded(
                child: Text(
                  step.label,
                  style: tt.bodyMedium?.copyWith(
                    color: step.done ? MiraiTokens.textTertiary : MiraiTokens.textPrimary,
                    decoration: step.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlashcardsHomeworkBanner extends StatelessWidget {
  const _FlashcardsHomeworkBanner({
    required this.current,
    required this.summaryTrimmed,
    required this.deckRepository,
    required this.isLocalOnlyDemo,
    required this.aiBusy,
    required this.hideQaSuggest,
    required this.onDismissQaSuggest,
    required this.onParseQuestionsFromMaterial,
    required this.onTapGenerate,
    required this.onTapGenerateVocabulary,
    required this.onOpenDeck,
    required this.onDeleteDeck,
  });

  final HomeworkItem current;
  final String? summaryTrimmed;
  final DeckRepository deckRepository;
  final bool isLocalOnlyDemo;
  final bool aiBusy;
  final bool hideQaSuggest;
  final VoidCallback onDismissQaSuggest;
  final VoidCallback onParseQuestionsFromMaterial;
  final VoidCallback onTapGenerate;
  final VoidCallback onTapGenerateVocabulary;
  final void Function(String deckId) onOpenDeck;
  final void Function(String deckId) onDeleteDeck;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final sid = (current.linkedDeckId ?? '').trim();
    if (sid.isEmpty) {
      final ext = (current.extractedText ?? '').trim();
      final vocabMode =
          current.isVocabularyHomework && current.vocabulary.isNotEmpty;
      final showQaBanner = !hideQaSuggest &&
          !vocabMode &&
          ext.isNotEmpty &&
          looksLikeQAndA(ext) &&
          kUseFirestoreHomework &&
          !isLocalOnlyDemo;

      final create = _FlashcardsCreateBanner(
        vocabularyMode: vocabMode,
        summaryTrimmed: summaryTrimmed,
        isLocalOnlyDemo: isLocalOnlyDemo,
        aiBusy: aiBusy,
        onTapGenerate: onTapGenerate,
        onTapGenerateVocabulary: onTapGenerateVocabulary,
      );

      if (!showQaBanner) return create;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(MiraiTokens.spaceMd),
            decoration: BoxDecoration(
              color: const Color(0x26FFC107),
              borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
              border: Border.all(color: const Color(0x66FFA000)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Det här ser ut som frågor med svar. Vill du använda dem direkt '
                  'istället för att låta AI hitta på nya?',
                  style: tt.bodyMedium?.copyWith(height: 1.45),
                ),
                const SizedBox(height: MiraiTokens.spaceSm),
                Wrap(
                  spacing: MiraiTokens.spaceSm,
                  runSpacing: MiraiTokens.spaceXs,
                  children: [
                    FilledButton(
                      onPressed: aiBusy ? null : onParseQuestionsFromMaterial,
                      child:
                          const Text('Använd frågorna i materialet'),
                    ),
                    TextButton(
                      onPressed: onDismissQaSuggest,
                      child: const Text('Nej, generera nya'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
          create,
        ],
      );
    }
    return _FlashcardsDeckBanner(
      key: ValueKey(sid),
      deckRepository: deckRepository,
      deckId: sid,
      homeworkId: current.id,
      onOpenDeck: onOpenDeck,
      onDeleteDeck: onDeleteDeck,
    );
  }
}

/// Visar info om kopplad deck samt senaste förhörsresultat (AP8).
class _FlashcardsDeckBanner extends StatefulWidget {
  const _FlashcardsDeckBanner({
    super.key,
    required this.deckRepository,
    required this.deckId,
    required this.homeworkId,
    required this.onOpenDeck,
    required this.onDeleteDeck,
  });

  final DeckRepository deckRepository;
  final String deckId;
  final String homeworkId;
  final void Function(String deckId) onOpenDeck;
  final void Function(String deckId) onDeleteDeck;

  @override
  State<_FlashcardsDeckBanner> createState() => _FlashcardsDeckBannerState();
}

class _FlashcardsDeckBannerState extends State<_FlashcardsDeckBanner> {
  late final Stream<FlashcardDeck?> _deckStream =
      widget.deckRepository.watchDeck(widget.deckId);
  late final Stream<List<Flashcard>> _cardsStream =
      widget.deckRepository.watchCardsInDeck(widget.deckId);
  late final SessionLogRepository _sessionLogRepo = kUseFirestoreHomework
      ? FirestoreSessionLogRepository()
      : DevSessionLogRepository();
  late final Stream<List<StudySessionLog>> _logStream =
      _sessionLogRepo.watchLogsForHomework(widget.homeworkId);

  String _formatLogTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
    final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (isToday) return 'idag $timeStr';
    if (isYesterday) return 'igår $timeStr';
    return '${dt.day}/${dt.month} $timeStr';
  }

  void _showLogDetailsSheet(BuildContext context, StudySessionLog log) {
    final tt = Theme.of(context).textTheme;
    final minutes = (log.durationSeconds / 60).ceil();
    final durationStr = log.durationSeconds < 60
        ? '${log.durationSeconds} sekunder'
        : '$minutes minuter';

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MiraiTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resultat från senaste förhöret',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: MiraiTokens.spaceMd),
              Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: MiraiTokens.success, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Gick bra: ${log.correctCards} ord',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (log.missedFronts.isNotEmpty) ...[
                const SizedBox(height: MiraiTokens.spaceSm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.replay_rounded,
                        color: MiraiTokens.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Behöver övas:',
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: MiraiTokens.danger,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            log.missedFronts.join(', '),
                            style: tt.bodySmall?.copyWith(color: MiraiTokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: MiraiTokens.spaceSm),
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      color: MiraiTokens.textTertiary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Tid: $durationStr',
                    style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: MiraiTokens.spaceLg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Stäng'),
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
    return StreamBuilder<FlashcardDeck?>(
      stream: _deckStream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 56,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final deck = snap.data;
        if (deck == null) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<List<Flashcard>>(
          stream: _cardsStream,
          builder: (context, cardSnap) {
            final dueCount = cardSnap.hasData
                ? SpacedRepetition.filterDue(cardSnap.data!, DateTime.now()).length
                : null;
            return InkWell(
              borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
              onTap: () => widget.onOpenDeck(deck.id),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MiraiTokens.bgRaised,
                  borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                  border: Border.all(
                    color: MiraiTokens.borderSubtle,
                    width: MiraiTokens.borderThin,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.style_rounded, color: MiraiTokens.accent, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${deck.cardCount} flashcards',
                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          if (dueCount != null)
                            RichText(
                              text: TextSpan(
                                style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                                children: [
                                  TextSpan(text: '${deck.cardCount} kort · '),
                                  if (dueCount == 0)
                                    const TextSpan(text: 'allt klart')
                                  else
                                    TextSpan(
                                      text: '$dueCount att repetera',
                                      style: tt.bodySmall?.copyWith(color: MiraiTokens.accent),
                                    ),
                                ],
                              ),
                            )
                          else
                            Text(
                              'Laddar repetition...',
                              style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            'Senast uppdaterad: ${_flashcardsRelativeUpdated(deck.updatedAt)}',
                            style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                          ),
                          StreamBuilder<List<StudySessionLog>>(
                            stream: _logStream,
                            builder: (context, logSnap) {
                              final logs = logSnap.data ?? [];
                              if (logs.isEmpty) return const SizedBox.shrink();
                              final latest = logs.first;
                              final timeStr = _formatLogTime(latest.completedAt);
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: InkWell(
                                  onTap: () => _showLogDetailsSheet(context, latest),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.history_rounded,
                                          size: 14, color: MiraiTokens.accent),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Senaste förhör: $timeStr · ${latest.correctCards} av ${latest.totalCards} rätt',
                                        style: tt.bodySmall?.copyWith(
                                          color: MiraiTokens.accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(Icons.chevron_right_rounded,
                                          size: 14, color: MiraiTokens.accent),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Ta bort lek',
                      color: MiraiTokens.textTertiary,
                      onPressed: () => widget.onDeleteDeck(deck.id),
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

class _FlashcardsCreateBanner extends StatelessWidget {
  const _FlashcardsCreateBanner({
    required this.vocabularyMode,
    required this.summaryTrimmed,
    required this.isLocalOnlyDemo,
    required this.aiBusy,
    required this.onTapGenerate,
    required this.onTapGenerateVocabulary,
  });

  final bool vocabularyMode;
  final String? summaryTrimmed;
  final bool isLocalOnlyDemo;
  final bool aiBusy;
  final VoidCallback onTapGenerate;
  final VoidCallback onTapGenerateVocabulary;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasSummary =
        summaryTrimmed != null && summaryTrimmed!.trim().isNotEmpty;
    final needsFirebase = !kUseFirestoreHomework;
    final tip = () {
      if (vocabularyMode) {
        if (needsFirebase) return 'Kräver Firebase';
        if (isLocalOnlyDemo) return 'Den här läxan är inte sparad i molnet';
        return '';
      }
      if (needsFirebase) return 'Kräver Firebase';
      if (isLocalOnlyDemo) {
        return 'Den här läxan är inte sparad i molnet';
      }
      if (!hasSummary) return 'Generera sammanfattning först';
      return '';
    }();

    final canTapVocab =
        vocabularyMode && !needsFirebase && !isLocalOnlyDemo && !aiBusy;
    final canTapSummary =
        !vocabularyMode &&
        hasSummary &&
        !needsFirebase &&
        !isLocalOnlyDemo &&
        !aiBusy;

    final VoidCallback runGenerate =
        vocabularyMode ? onTapGenerateVocabulary : onTapGenerate;
    final canTap = vocabularyMode ? canTapVocab : canTapSummary;

    Widget generera = FilledButton(
      onPressed: canTap ? runGenerate : null,
      child: const Text('Generera'),
    );
    if (tip.isNotEmpty && !canTap) {
      generera = Tooltip(
        message: tip,
        child: generera,
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MiraiTokens.bgRaised,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        border: Border.all(
          color: MiraiTokens.borderSubtle,
          width: MiraiTokens.borderThin,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.style_outlined, color: MiraiTokens.accent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vocabularyMode ? 'Glos-flashcards' : 'Skapa flashcards',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  vocabularyMode
                      ? 'Ett kort fram & tillbaka per glosa'
                      : 'AI gör 10 frågor från sammanfattningen',
                  style:
                      tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                ),
              ],
            ),
          ),
          generera,
        ],
      ),
    );
  }
}

class _MathProblemPanel extends StatelessWidget {
  const _MathProblemPanel({
    required this.entry,
    required this.index,
    required this.aiBusy,
    required this.varyBlocked,
    required this.onExplain,
    required this.onVary,
  });

  final MathProblemEntry entry;
  final int index;
  final bool aiBusy;
  final bool varyBlocked;
  final VoidCallback onExplain;
  final VoidCallback onVary;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: MiraiTokens.bgRaised,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        border: Border.all(color: MiraiTokens.borderSubtle),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        childrenPadding:
            const EdgeInsets.fromLTRB(12, 0, 12, MiraiTokens.spaceMd),
        title: Text(
          entry.originalText,
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '#${index + 1}',
          style: tt.labelSmall?.copyWith(color: MiraiTokens.textTertiary),
        ),
        children: [
          if ((entry.explanation ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: MiraiTokens.spaceSm),
              child: Text(
                entry.explanation!,
                style: tt.bodySmall?.copyWith(height: 1.45),
              ),
            ),
          Wrap(
            spacing: MiraiTokens.spaceSm,
            runSpacing: MiraiTokens.spaceXs,
            children: [
              FilledButton.icon(
                onPressed: aiBusy ? null : onExplain,
                icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                label: const Text('Förklara'),
              ),
              Tooltip(
                message: varyBlocked
                    ? 'Variera siffror är pausad för högre årskurs.'
                    : 'Nya siffror, samma uppgift',
                child: FilledButton.tonalIcon(
                  onPressed: (aiBusy || varyBlocked) ? null : onVary,
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Variera'),
                ),
              ),
            ],
          ),
          if (entry.variants.isNotEmpty) ...[
            const SizedBox(height: MiraiTokens.spaceSm),
            Text(
              'Varianter',
              style:
                  tt.labelSmall?.copyWith(color: MiraiTokens.textSecondary),
            ),
            const SizedBox(height: MiraiTokens.spaceXs),
            for (final v in entry.variants)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('· $v', style: tt.bodySmall),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: MiraiTokens.bgRaised,
      borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
            border: Border.all(
              color: MiraiTokens.borderSubtle,
              width: MiraiTokens.borderThin,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: MiraiTokens.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: tt.labelSmall?.copyWith(
                  fontSize: 11,
                  color: MiraiTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MiraiTokens.bgRaised,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

String _flashcardsRelativeUpdated(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'just nu';
  if (diff.inHours < 1) return '${diff.inMinutes} min sedan';
  if (diff.inDays < 1) return '${diff.inHours} tim sedan';
  if (diff.inDays == 1) return 'Igår';
  if (diff.inDays < 7) return '${diff.inDays} dagar sedan';
  return '${t.day.toString().padLeft(2, '0')}-${t.month.toString().padLeft(2, '0')}-${t.year}';
}

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _deadlineLabel(DateTime? dueAt) {
  if (dueAt == null) return 'Ingen deadline';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final diff = due.difference(today).inDays;
  if (diff == 0) return 'Idag';
  if (diff == 1) return 'Imorgon';
  if (diff > 1 && diff <= 6) return 'Om $diff dagar';
  const days = ['Måndag', 'Tisdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lördag', 'Söndag'];
  const months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'maj',
    'jun',
    'jul',
    'aug',
    'sep',
    'okt',
    'nov',
    'dec',
  ];
  return '${days[due.weekday - 1]} ${due.day} ${months[due.month - 1]}';
}

String _detailMeta(HomeworkItem item) {
  final d = _deadlineLabel(item.dueAt);
  final f = item.attachmentFileName?.trim();
  if (f != null && f.isNotEmpty) return '$d · $f';
  return d;
}

/// Visar bilagor grupperat per roll och låter användaren ändra rollen.
class _SourcesPanel extends StatefulWidget {
  const _SourcesPanel({
    required this.attachments,
    required this.aiBusy,
    required this.isLocalOnlyDemo,
    required this.onChangeRole,
    required this.onExtractAt,
  });

  final List<HomeworkAttachment> attachments;
  final bool aiBusy;
  final bool isLocalOnlyDemo;
  final Future<void> Function(int index, HomeworkAttachmentRole role) onChangeRole;
  final Future<void> Function(int index) onExtractAt;

  @override
  State<_SourcesPanel> createState() => _SourcesPanelState();
}

class _SourcesPanelState extends State<_SourcesPanel> {
  HomeworkAttachmentRole _selected = HomeworkAttachmentRole.summary;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final rolesPresent = <HomeworkAttachmentRole>{
      for (final a in widget.attachments) a.role,
    };
    if (!rolesPresent.contains(_selected)) {
      _selected = rolesPresent.contains(HomeworkAttachmentRole.summary)
          ? HomeworkAttachmentRole.summary
          : (rolesPresent.contains(HomeworkAttachmentRole.qa)
              ? HomeworkAttachmentRole.qa
              : (rolesPresent.contains(HomeworkAttachmentRole.mixed)
                  ? HomeworkAttachmentRole.mixed
                  : HomeworkAttachmentRole.other));
    }

    final indexed = <MapEntry<int, HomeworkAttachment>>[];
    for (var i = 0; i < widget.attachments.length; i++) {
      indexed.add(MapEntry(i, widget.attachments[i]));
    }
    final visible = indexed
        .where((e) => e.value.role == _selected)
        .toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: MiraiTokens.bgRaised,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        border: Border.all(
          color: MiraiTokens.borderSubtle,
          width: MiraiTokens.borderThin,
        ),
      ),
      padding: const EdgeInsets.all(MiraiTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MiraiTokens.spaceXs,
              vertical: MiraiTokens.spaceXs,
            ),
            child: Text(
              'KÄLLOR',
              style: tt.labelSmall?.copyWith(
                letterSpacing: 0.5,
                color: MiraiTokens.textTertiary,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final r in HomeworkAttachmentRole.values)
                  if (rolesPresent.contains(r))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          '${r.labelSv} · ${widget.attachments.where((a) => a.role == r).length}',
                        ),
                        selected: _selected == r,
                        onSelected: (s) {
                          if (s) setState(() => _selected = r);
                        },
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: MiraiTokens.spaceSm),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(MiraiTokens.spaceSm),
              child: Text(
                'Inga källor i kategorin.',
                style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
              ),
            )
          else
            for (final pair in visible)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  pair.value.role == HomeworkAttachmentRole.qa
                      ? Icons.quiz_outlined
                      : Icons.insert_drive_file_outlined,
                  color: MiraiTokens.textSecondary,
                ),
                title: Text(
                  pair.value.fileName.trim().isEmpty
                      ? 'Bilaga ${pair.key + 1}'
                      : pair.value.fileName,
                  style: tt.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  (pair.value.extractedText ?? '').trim().isNotEmpty
                      ? 'Text extraherad'
                      : 'Ej extraherad',
                  style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                ),
                trailing: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if ((pair.value.extractedText ?? '').trim().isEmpty)
                      IconButton(
                        tooltip: widget.isLocalOnlyDemo
                            ? 'Inte sparad i molnet'
                            : 'Extrahera text',
                        icon: const Icon(Icons.text_snippet_outlined),
                        onPressed: (widget.aiBusy || widget.isLocalOnlyDemo)
                            ? null
                            : () => widget.onExtractAt(pair.key),
                      ),
                    PopupMenuButton<HomeworkAttachmentRole>(
                      tooltip: 'Roll',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (r) => widget.onChangeRole(pair.key, r),
                      itemBuilder: (ctx) => [
                        for (final r in HomeworkAttachmentRole.values)
                          PopupMenuItem(
                            value: r,
                            child: Row(
                              children: [
                                if (r == pair.value.role)
                                  const Icon(Icons.check_rounded, size: 16)
                                else
                                  const SizedBox(width: 16),
                                const SizedBox(width: 8),
                                Text(r.labelSv),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _PipelineStatusBanner extends StatelessWidget {
  const _PipelineStatusBanner({required this.homeworkId});

  final String homeworkId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SnapPipelineService.instance,
      builder: (context, _) {
        final task = SnapPipelineService.instance.getTask(homeworkId);
        if (task == null || !task.isRunning) return const SizedBox.shrink();
        final tt = Theme.of(context).textTheme;
        return Container(
          margin: const EdgeInsets.only(bottom: MiraiTokens.spaceMd),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: MiraiTokens.accentSoft,
            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            border: Border.all(
              color: MiraiTokens.accent.withValues(alpha: 0.3),
              width: MiraiTokens.borderThin,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: MiraiTokens.spaceSm),
              Expanded(
                child: Text(
                  'Läser in läxan… (steg ${task.currentStep + 1} av ${task.totalSteps})',
                  style: tt.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: MiraiTokens.accent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

