import 'dart:async';

import '../config.dart';
import '../models/homework_item.dart';
import '../models/vocabulary_entry.dart';
import 'homework_repository.dart';

/// In-memory homework for local UX development without Firebase.
class DevHomeworkRepository implements HomeworkRepository {
  DevHomeworkRepository() {
    _seed();
    _emit();
  }

  final List<HomeworkItem> _items = [];
  final StreamController<void> _tick = StreamController<void>.broadcast();

  void _emit() {
    if (!_tick.isClosed) _tick.add(null);
  }

  void _seed() {
    final now = DateTime.now();
    _items.add(
      HomeworkItem(
        id: 'dev-1',
        familyId: kDevFamilyId,
        assignedToUserId: kDevAssignedToUserId,
        subject: 'Historia',
        topic: 'Vikingatiden · v.4–7',
        title: 'Glosor + källkritik',
        details: 'Repetera begrepp från lektionerna om vikingatiden.',
        extractedText:
            'Vikingatiden varade ungefär från 800 till 1050. Vikinger seglade '
            'över stora hav och handlade också. Byn och tinget var viktiga '
            'för beslut.',
        summary:
            'Läs om vikingatid, handel och hur man fattade beslut (tinget). '
            'Glosa begreppen inför nästa lektion.',
        ttsPreference: HomeworkTtsPreference.system,
        dueAt: now.add(const Duration(days: 2)),
        status: HomeworkStatus.todo,
        subtasks: const [
          HomeworkSubtask(id: 's1', title: 'Läs texten'),
          HomeworkSubtask(id: 's2', title: 'Svara skriftligt', done: false),
        ],
        createdAt: now,
        updatedAt: now,
        homeworkType: 'text',
        vocabulary: const [],
        mathProblems: const [],
        gradeHint: null,
      ),
    );
    _items.add(
      HomeworkItem(
        id: 'dev-2',
        familyId: kDevFamilyId,
        assignedToUserId: kDevAssignedToUserId,
        subject: 'Matematik',
        title: 'Övningar s. 42',
        dueAt: now.add(const Duration(days: 1)),
        status: HomeworkStatus.inProgress,
        createdAt: now,
        updatedAt: now,
        homeworkType: 'text',
        vocabulary: const [],
        mathProblems: const [],
        gradeHint: null,
      ),
    );
    _items.add(
      HomeworkItem(
        id: 'dev-3',
        familyId: kDevFamilyId,
        assignedToUserId: kDevAssignedToUserId,
        subject: 'Engelska',
        topic: 'Unit 4 · Food & Animals',
        title: 'Engelska glosor v.36',
        details: 'Träna på veckans glosor inför förhöret på fredag.',
        extractedText:
            'apple - äpple\nbread - bröd\ncat - katt\ndog - hund\nelephant - elefant',
        summary: 'Öva på mat och djur på engelska.',
        ttsPreference: HomeworkTtsPreference.system,
        dueAt: now.add(const Duration(days: 1)),
        status: HomeworkStatus.todo,
        subtasks: const [
          HomeworkSubtask(id: 's1', title: 'Läs glosorna'),
          HomeworkSubtask(id: 's2', title: 'Starta förhör', done: false),
        ],
        createdAt: now,
        updatedAt: now,
        homeworkType: 'vocabulary',
        vocabulary: const [
          VocabularyEntry(term: 'apple', translation: 'äpple'),
          VocabularyEntry(term: 'bread', translation: 'bröd'),
          VocabularyEntry(term: 'cat', translation: 'katt'),
          VocabularyEntry(term: 'dog', translation: 'hund'),
          VocabularyEntry(term: 'elephant', translation: 'elefant'),
        ],
        mathProblems: const [],
        gradeHint: null,
      ),
    );
  }

  List<HomeworkItem> _filtered(String familyId, String? assignedToUserId) {
    var list = _items.where((h) => h.familyId == familyId).toList();
    if (assignedToUserId != null && assignedToUserId.isNotEmpty) {
      list = list.where((h) => h.assignedToUserId == assignedToUserId).toList();
    }
    list.sort((a, b) {
      if (a.dueAt == null && b.dueAt == null) {
        return b.updatedAt.compareTo(a.updatedAt);
      }
      if (a.dueAt == null) return 1;
      if (b.dueAt == null) return -1;
      return a.dueAt!.compareTo(b.dueAt!);
    });
    return list;
  }

  @override
  Stream<List<HomeworkItem>> watchForFamily({
    required String familyId,
    String? assignedToUserId,
  }) {
    return Stream<List<HomeworkItem>>.multi((listener) {
      listener.add(_filtered(familyId, assignedToUserId));
      final sub = _tick.stream.listen((_) {
        listener.add(_filtered(familyId, assignedToUserId));
      });
      listener.onCancel = () => sub.cancel();
    });
  }

  @override
  Future<String> create(HomeworkItem draft) async {
    final now = DateTime.now();
    final id = 'dev-${now.microsecondsSinceEpoch}';
    _items.add(
      HomeworkItem(
        id: id,
        familyId: draft.familyId,
        assignedToUserId: draft.assignedToUserId,
        subject: draft.subject,
        topic: draft.topic,
        title: draft.title,
        details: draft.details,
        extractedText: draft.extractedText,
        summary: draft.summary,
        ttsPreference: draft.ttsPreference,
        dueAt: draft.dueAt,
        status: draft.status,
        subtasks: draft.subtasks,
        steps: draft.steps,
        linkedDeckId: draft.linkedDeckId,
        plannerEventId: draft.plannerEventId,
        recurrenceRule: draft.recurrenceRule,
        source: draft.source,
        createdByUserId: draft.createdByUserId,
        attachmentFileName: draft.attachmentFileName,
        attachmentMimeType: draft.attachmentMimeType,
        attachmentStorageUrl: draft.attachmentStorageUrl,
        attachments: draft.attachments,
        homeworkType: draft.homeworkType,
        vocabulary: draft.vocabulary,
        mathProblems: draft.mathProblems,
        gradeHint: draft.gradeHint,
        createdAt: now,
        updatedAt: now,
      ),
    );
    _emit();
    return id;
  }

  @override
  Future<void> update(HomeworkItem item) async {
    final i = _items.indexWhere((h) => h.id == item.id);
    if (i < 0) return;
    final now = DateTime.now();
    _items[i] = HomeworkItem(
      id: item.id,
      familyId: item.familyId,
      assignedToUserId: item.assignedToUserId,
      subject: item.subject,
      topic: item.topic,
      title: item.title,
      details: item.details,
      extractedText: item.extractedText,
      summary: item.summary,
      ttsPreference: item.ttsPreference,
      dueAt: item.dueAt,
      status: item.status,
      subtasks: item.subtasks,
      steps: item.steps,
      linkedDeckId: item.linkedDeckId,
      plannerEventId: item.plannerEventId,
      recurrenceRule: item.recurrenceRule,
      source: item.source,
      createdByUserId: item.createdByUserId,
      attachmentFileName: item.attachmentFileName,
      attachmentMimeType: item.attachmentMimeType,
      attachmentStorageUrl: item.attachmentStorageUrl,
      attachments: item.attachments,
      homeworkType: item.homeworkType,
      vocabulary: item.vocabulary,
      mathProblems: item.mathProblems,
      gradeHint: item.gradeHint,
      createdAt: item.createdAt,
      updatedAt: now,
    );
    _emit();
  }

  @override
  Future<void> delete(String homeworkId) async {
    _items.removeWhere((h) => h.id == homeworkId);
    _emit();
  }
}
