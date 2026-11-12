import 'package:flutter/foundation.dart';

import '../data/homework_repository.dart';
import '../data/homework_storage_upload.dart';
import '../models/homework_attachment.dart';
import '../models/homework_item.dart';
import '../services/ai_service.dart';
import '../services/notification_service.dart';
import '../util/merge_extracted_texts.dart';
import '../util/subject_suggestions.dart';
import '../screens/homework_snap_flow_screen.dart';

class SnapPipelineFile {
  const SnapPipelineFile({
    required this.bytes,
    required this.fileName,
    required this.mime,
  });

  final Uint8List bytes;
  final String fileName;
  final String mime;
}

enum SnapPipelineStage {
  saving,
  reading,
  merging,
  suggesting,
  done,
  failed,
}

class SnapPipelineTask {
  SnapPipelineTask({
    required this.homeworkId,
    required this.stage,
    this.currentStep = 0,
    this.totalSteps = 4,
    this.errorMsg,
    this.item,
    this.suggestion,
  });

  final String homeworkId;
  final SnapPipelineStage stage;
  final int currentStep;
  final int totalSteps;
  final String? errorMsg;
  final HomeworkItem? item;
  final HomeworkMetadataSuggestion? suggestion;

  bool get isRunning =>
      stage != SnapPipelineStage.done && stage != SnapPipelineStage.failed;
  bool get isDone => stage == SnapPipelineStage.done;
  bool get isFailed => stage == SnapPipelineStage.failed;

  String get stepLabel {
    switch (stage) {
      case SnapPipelineStage.saving:
        return 'Sparar läxan …';
      case SnapPipelineStage.reading:
        return 'Läser din läxa 👀';
      case SnapPipelineStage.merging:
        return 'Lägger ihop allt …';
      case SnapPipelineStage.suggesting:
        return 'Nästan klar – föreslår titel och datum …';
      case SnapPipelineStage.done:
        return 'Klar!';
      case SnapPipelineStage.failed:
        return 'Något gick fel: ${errorMsg ?? "Okänt fel"}';
    }
  }
}

class SnapPipelineService extends ChangeNotifier {
  SnapPipelineService({AiService? aiService}) : _aiService = aiService;
  static SnapPipelineService instance = SnapPipelineService();

  final Map<String, SnapPipelineTask> _tasks = {};
  AiService? _aiService;
  AiService get _ai => _aiService ??= AiService();

  SnapPipelineTask? getTask(String homeworkId) => _tasks[homeworkId];

  bool isRunning(String homeworkId) {
    final t = _tasks[homeworkId];
    return t != null && t.isRunning;
  }

  /// Startar pipelinen asynkront och returnerar skapade homeworkId så fort utkastet är sparat.
  Future<String> start({
    required HomeworkRepository repository,
    required String familyId,
    required String assignedToUserId,
    required List<SnapPipelineFile> files,
    SnapIntent intent = SnapIntent.homework,
    void Function(String homeworkId)? onDraftCreated,
  }) async {
    final now = DateTime.now();
    var draft = HomeworkItem(
      id: '',
      familyId: familyId,
      assignedToUserId: assignedToUserId,
      subject: 'Ämne',
      title: intent == SnapIntent.quiz ? 'Glosor' : 'Ny läxa',
      homeworkType: intent == SnapIntent.quiz ? 'vocabulary' : 'text',
      status: HomeworkStatus.todo,
      attachmentFileName: files.first.fileName,
      attachmentMimeType: files.first.mime,
      attachmentStorageUrl: null,
      createdAt: now,
      updatedAt: now,
    );

    final homeworkId = await repository.create(draft);
    draft = draft.copyWith(id: homeworkId);
    onDraftCreated?.call(homeworkId);

    _updateTask(
      homeworkId,
      SnapPipelineTask(
        homeworkId: homeworkId,
        stage: SnapPipelineStage.saving,
        currentStep: 0,
        item: draft,
      ),
    );

    // Kör pipeline asynkront så att användaren kan lämna vyn utan att avbryta processen (D6)
    _runPipelineAsync(
      repository: repository,
      homeworkId: homeworkId,
      initialDraft: draft,
      files: files,
      intent: intent,
    );

    return homeworkId;
  }

  void _updateTask(String homeworkId, SnapPipelineTask task) {
    _tasks[homeworkId] = task;
    notifyListeners();
  }

  Future<void> _runPipelineAsync({
    required HomeworkRepository repository,
    required String homeworkId,
    required HomeworkItem initialDraft,
    required List<SnapPipelineFile> files,
    required SnapIntent intent,
  }) async {
    try {
      final attachments = <HomeworkAttachment>[];
      final nowTs = DateTime.now();
      for (final f in files) {
        final url = await uploadHomeworkAttachmentBytes(
          familyId: initialDraft.familyId,
          homeworkId: homeworkId,
          fileName: f.fileName,
          bytes: f.bytes,
          contentType: f.mime,
        );
        attachments.add(
          HomeworkAttachment(
            fileName: f.fileName,
            mimeType: f.mime,
            storageUrl: url,
            extractedText: null,
            addedAt: nowTs,
          ),
        );
      }
      final primary = attachments.first;
      var draft = initialDraft.copyWith(
        attachmentStorageUrl: primary.storageUrl,
        attachmentFileName: primary.fileName,
        attachmentMimeType: primary.mimeType,
        attachments: attachments,
      );
      await repository.update(draft);

      _updateTask(
        homeworkId,
        SnapPipelineTask(
          homeworkId: homeworkId,
          stage: SnapPipelineStage.reading,
          currentStep: 1,
          item: draft,
        ),
      );

      var successCount = 0;
      for (var i = 0; i < files.length; i++) {
        try {
          final extracted = await _ai.extractFromAttachment(
            homeworkId,
            attachmentIndex: i,
          );
          draft = withAttachmentExtractApplied(draft, i, extracted.text);
          await repository.update(draft);
          successCount++;
        } catch (e) {
          debugPrint('[SnapPipelineService] extract idx $i failed: $e');
        }
      }

      if (successCount == 0) {
        _updateTask(
          homeworkId,
          SnapPipelineTask(
            homeworkId: homeworkId,
            stage: SnapPipelineStage.failed,
            errorMsg: 'Kunde inte läsa text från bilagorna',
            item: draft,
          ),
        );
        return;
      }

      _updateTask(
        homeworkId,
        SnapPipelineTask(
          homeworkId: homeworkId,
          stage: SnapPipelineStage.merging,
          currentStep: 2,
          item: draft,
        ),
      );

      final merged = (draft.extractedText ?? '').trim();
      if (merged.isEmpty) {
        _updateTask(
          homeworkId,
          SnapPipelineTask(
            homeworkId: homeworkId,
            stage: SnapPipelineStage.failed,
            errorMsg: 'Ingen text hittades i bilderna',
            item: draft,
          ),
        );
        return;
      }

      _updateTask(
        homeworkId,
        SnapPipelineTask(
          homeworkId: homeworkId,
          stage: SnapPipelineStage.suggesting,
          currentStep: 3,
          item: draft,
        ),
      );

      HomeworkMetadataSuggestion? suggestion;
      try {
        suggestion = await _ai.suggestHomeworkMetadata(
          text: merged,
          knownSubjects: kStandardSchoolSubjects,
        );

        String finalType = suggestion.homeworkType;
        if (intent == SnapIntent.quiz) {
          if (suggestion.confidence > 0.4 &&
              suggestion.homeworkType == 'vocabulary') {
            finalType = 'vocabulary';
          } else if (suggestion.confidence >= 0.6) {
            finalType = suggestion.homeworkType;
          } else {
            finalType = 'vocabulary';
          }
        }

        // Steg 4 (D6): Skriv förslaget direkt till läxdokumentet i Firestore
        draft = draft.copyWith(
          title: suggestion.title,
          subject: suggestion.subject,
          dueAt: suggestion.dueAt,
          homeworkType: finalType,
        );
        await repository.update(draft);
      } catch (e) {
        debugPrint('[SnapPipelineService] suggestMetadata failed: $e');
      }

      _updateTask(
        homeworkId,
        SnapPipelineTask(
          homeworkId: homeworkId,
          stage: SnapPipelineStage.done,
          currentStep: 4,
          item: draft,
          suggestion: suggestion,
        ),
      );

      // Notis när analysen är klar
      await NotificationService.instance.showHomeworkProcessed(
        title: draft.title,
        homeworkId: draft.id,
      );
    } catch (e) {
      _updateTask(
        homeworkId,
        SnapPipelineTask(
          homeworkId: homeworkId,
          stage: SnapPipelineStage.failed,
          errorMsg: 'Ett fel uppstod: $e',
          item: initialDraft,
        ),
      );
    }
  }
}
