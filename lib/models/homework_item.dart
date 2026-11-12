import 'package:cloud_firestore/cloud_firestore.dart';

import 'homework_attachment.dart';
import 'math_problem_entry.dart';
import 'vocabulary_entry.dart';

enum HomeworkStatus {
  todo,
  inProgress,
  done,
  archived;

  String get firestoreValue {
    switch (this) {
      case HomeworkStatus.todo:
        return 'todo';
      case HomeworkStatus.inProgress:
        return 'in_progress';
      case HomeworkStatus.done:
        return 'done';
      case HomeworkStatus.archived:
        return 'archived';
    }
  }

  static HomeworkStatus fromFirestore(String? value) {
    switch (value) {
      case 'in_progress':
        return HomeworkStatus.inProgress;
      case 'done':
        return HomeworkStatus.done;
      case 'archived':
        return HomeworkStatus.archived;
      case 'todo':
      default:
        return HomeworkStatus.todo;
    }
  }

  /// Swedish UI label.
  String get labelSv {
    switch (this) {
      case HomeworkStatus.todo:
        return 'Att göra';
      case HomeworkStatus.inProgress:
        return 'Pågår';
      case HomeworkStatus.done:
        return 'Klar';
      case HomeworkStatus.archived:
        return 'Arkiverad';
    }
  }
}

/// Vilken röstmotor som ska användas när uppläsning implementeras (La Familia / My Mirai delar fält).
enum HomeworkTtsPreference {
  none,
  system,
  cloud;

  String get firestoreValue => name;

  static HomeworkTtsPreference fromFirestore(String? value) {
    switch (value) {
      case 'system':
        return HomeworkTtsPreference.system;
      case 'cloud':
        return HomeworkTtsPreference.cloud;
      case 'none':
      default:
        return HomeworkTtsPreference.none;
    }
  }

  String get labelSv {
    switch (this) {
      case HomeworkTtsPreference.none:
        return 'Ingen uppläsning';
      case HomeworkTtsPreference.system:
        return 'Enhetsröst (på enheten)';
      case HomeworkTtsPreference.cloud:
        return 'Premiumröst (moln)';
    }
  }
}

class HomeworkSubtask {
  const HomeworkSubtask({
    required this.id,
    required this.title,
    this.done = false,
  });

  final String id;
  final String title;
  final bool done;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'done': done,
      };

  static HomeworkSubtask fromMap(Map<String, dynamic> m) {
    return HomeworkSubtask(
      id: m['id'] as String? ?? '',
      title: m['title'] as String? ?? '',
      done: m['done'] as bool? ?? false,
    );
  }

  HomeworkSubtask copyWith({String? title, bool? done}) {
    return HomeworkSubtask(
      id: id,
      title: title ?? this.title,
      done: done ?? this.done,
    );
  }
}

class HomeworkStep {
  const HomeworkStep({
    required this.id,
    required this.label,
    this.done = false,
  });

  final String id;
  final String label;
  final bool done;

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'done': done,
      };

  static HomeworkStep fromMap(Map<String, dynamic> m) {
    return HomeworkStep(
      id: m['id'] as String? ?? '',
      label: m['label'] as String? ?? '',
      done: m['done'] as bool? ?? false,
    );
  }

  HomeworkStep copyWith({bool? done}) {
    return HomeworkStep(id: id, label: label, done: done ?? this.done);
  }
}

class HomeworkItem {
  const HomeworkItem({
    required this.id,
    required this.familyId,
    required this.assignedToUserId,
    required this.subject,
    this.topic,
    required this.title,
    this.details,
    /// Text ur material: OCR, inklistrat eller importerat. Underlag för sammanfattning & TTS.
    this.extractedText,
    /// Kort version av uppgiften (manuellt eller AI — granska alltid).
    this.summary,
    this.ttsPreference = HomeworkTtsPreference.none,
    this.dueAt,
    required this.status,
    this.subtasks = const [],
    this.steps = const [],
    this.linkedDeckId,
    this.plannerEventId,
    this.recurrenceRule,
    this.source,
    this.createdByUserId,
    /// Äldre fält — läs [attachments].
    this.attachmentFileName,
    this.attachmentMimeType,
    this.attachmentStorageUrl,
    this.attachments = const [],

    /// `text` | `vocabulary` | `math` (Chunk N–O).
    this.homeworkType = 'text',
    this.vocabulary = const [],
    this.mathProblems = const [],

    /// Årskurs 1–9 när känt — används för mattesäkerhetsgräns (åk 7+).
    this.gradeHint,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String assignedToUserId;
  final String subject;
  /// Fritext: tema, period, kapitel (t.ex. "Vikingatiden v.4–7").
  final String? topic;
  final String title;
  final String? details;
  final String? extractedText;
  final String? summary;
  final HomeworkTtsPreference ttsPreference;
  final DateTime? dueAt;
  final HomeworkStatus status;
  final List<HomeworkSubtask> subtasks;
  final List<HomeworkStep> steps;
  final String? linkedDeckId;
  final String? plannerEventId;
  final String? recurrenceRule;
  final String? source;
  final String? createdByUserId;

  /// @deprecated Erstatts av [attachments].
  final String? attachmentFileName;

  /// @deprecated Erstatts av [attachments].
  final String? attachmentMimeType;

  /// @deprecated Erstatts av [attachments].
  final String? attachmentStorageUrl;

  /// Bild-, PDF-, Word-källor mm. Tom om endast äldre fält används (läses ihop i [fromFirestore]).
  final List<HomeworkAttachment> attachments;

  /// `text` | `vocabulary` | `math`
  final String homeworkType;
  final List<VocabularyEntry> vocabulary;
  final List<MathProblemEntry> mathProblems;
  final int? gradeHint;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isVocabularyHomework => homeworkType == 'vocabulary';
  bool get isMathHomework => homeworkType == 'math';

  static HomeworkItem fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return fromData(doc.id, doc.data() ?? {});
  }

  static HomeworkItem fromData(String id, Map<String, dynamic> data) {
    final due = data['dueAt'];
    final created = data['createdAt'];
    final updated = data['updatedAt'];
    final subRaw = data['subtasks'];
    final subtasks = <HomeworkSubtask>[];
    if (subRaw is List) {
      for (final e in subRaw) {
        if (e is Map<String, dynamic>) {
          subtasks.add(HomeworkSubtask.fromMap(e));
        }
      }
    }
    final stepsRaw = data['steps'];
    final steps = <HomeworkStep>[];
    if (stepsRaw is List) {
      for (final e in stepsRaw) {
        if (e is Map<String, dynamic>) {
          steps.add(HomeworkStep.fromMap(e));
        }
      }
    }
    final vocab = <VocabularyEntry>[];
    final vRaw = data['vocabulary'];
    if (vRaw is List) {
      for (final e in vRaw) {
        if (e is Map<String, dynamic>) {
          final ve = VocabularyEntry.fromMap(e);
          if (ve.isValid) vocab.add(ve);
        }
      }
    }
    final mathRaw = data['mathProblems'];
    final math = <MathProblemEntry>[];
    if (mathRaw is List) {
      for (final e in mathRaw) {
        if (e is Map<String, dynamic>) math.add(MathProblemEntry.fromMap(e));
      }
    }
    final gh = data['gradeHint'];
    final createdDate =
        created is Timestamp ? created.toDate() : DateTime.now();
    final updatedDate =
        updated is Timestamp ? updated.toDate() : DateTime.now();

    final attList = <HomeworkAttachment>[];
    final rawAtt = data['attachments'];
    if (rawAtt is List) {
      for (final e in rawAtt) {
        if (e is Map<String, dynamic>) {
          attList.add(HomeworkAttachment.fromMap(e));
        }
      }
    }
    final rawLegacyUrl = data['attachmentStorageUrl'];
    final legacyUrl = rawLegacyUrl is String ? rawLegacyUrl.trim() : '';
    if (attList.isEmpty && legacyUrl.isNotEmpty) {
      final fn = data['attachmentFileName'] as String?;
      final mt = data['attachmentMimeType'] as String?;
      attList.add(
        HomeworkAttachment(
          fileName: (fn != null && fn.trim().isNotEmpty) ? fn.trim() : 'bilaga',
          mimeType: (mt != null && mt.trim().isNotEmpty)
              ? mt.trim()
              : 'application/octet-stream',
          storageUrl: legacyUrl,
          extractedText: null,
          addedAt: createdDate,
        ),
      );
    }

    return HomeworkItem(
      id: id,
      familyId: data['familyId'] as String? ?? '',
      assignedToUserId: data['assignedToUserId'] as String? ?? '',
      subject: data['subject'] as String? ?? '',
      topic: data['topic'] as String?,
      title: data['title'] as String? ?? '',
      details: data['details'] as String?,
      extractedText: data['extractedText'] as String?,
      summary: data['summary'] as String?,
      ttsPreference: HomeworkTtsPreference.fromFirestore(
        data['ttsPreference'] as String?,
      ),
      dueAt: due is Timestamp ? due.toDate() : null,
      status: HomeworkStatus.fromFirestore(data['status'] as String?),
      subtasks: subtasks,
      steps: steps,
      linkedDeckId: data['linkedDeckId'] as String?,
      plannerEventId: data['plannerEventId'] as String?,
      recurrenceRule: data['recurrenceRule'] as String?,
      source: data['source'] as String?,
      createdByUserId: data['createdByUserId'] as String?,
      attachmentFileName: data['attachmentFileName'] as String?,
      attachmentMimeType: data['attachmentMimeType'] as String?,
      attachmentStorageUrl: data['attachmentStorageUrl'] as String?,
      attachments: attList,
      homeworkType: () {
        final ht = (data['homeworkType'] as String?)?.trim();
        if (ht == null || ht.isEmpty) return 'text';
        return ht;
      }(),
      vocabulary: vocab,
      mathProblems: math,
      gradeHint: gh is int ? gh : (gh is num ? gh.toInt() : null),
      createdAt: createdDate,
      updatedAt: updatedDate,
    );
  }

  Map<String, dynamic> toFirestoreCreate({
    required DateTime now,
  }) {
    return {
      'familyId': familyId,
      'assignedToUserId': assignedToUserId,
      'subject': subject,
      'topic': topic,
      'title': title,
      'details': details,
      'extractedText': extractedText,
      'summary': summary,
      'ttsPreference': ttsPreference.firestoreValue,
      'dueAt': dueAt != null ? Timestamp.fromDate(dueAt!) : null,
      'status': status.firestoreValue,
      'subtasks': subtasks.map((s) => s.toMap()).toList(),
      'steps': steps.map((s) => s.toMap()).toList(),
      'linkedDeckId': linkedDeckId,
      'plannerEventId': plannerEventId,
      'recurrenceRule': recurrenceRule,
      'source': source ?? 'my_mirai',
      if (createdByUserId != null) 'createdByUserId': createdByUserId,
      'attachments': attachments.map((a) => a.toMap()).toList(),
      if (attachments.isNotEmpty) ...{
        // Speglar första bilagan till äldre fält — äldre/extraherings‑CF och verktyg förväntar sig dem.
        'attachmentFileName': attachments.first.fileName,
        'attachmentMimeType': attachments.first.mimeType,
        'attachmentStorageUrl': attachments.first.storageUrl,
      } else ...{
        'attachmentFileName': attachmentFileName,
        'attachmentMimeType': attachmentMimeType,
        'attachmentStorageUrl': attachmentStorageUrl,
      },
      'homeworkType': homeworkType,
      'vocabulary': vocabulary.map((e) => e.toMap()).toList(),
      'mathProblems': mathProblems.map((e) => e.toMap()).toList(),
      if (gradeHint != null) 'gradeHint': gradeHint,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    };
  }

  Map<String, dynamic> toFirestoreUpdate({
    required DateTime now,
  }) {
    return {
      'familyId': familyId,
      'assignedToUserId': assignedToUserId,
      'subject': subject,
      'topic': topic,
      'title': title,
      'details': details,
      'extractedText': extractedText,
      'summary': summary,
      'ttsPreference': ttsPreference.firestoreValue,
      'dueAt': dueAt != null ? Timestamp.fromDate(dueAt!) : null,
      'status': status.firestoreValue,
      'subtasks': subtasks.map((s) => s.toMap()).toList(),
      'steps': steps.map((s) => s.toMap()).toList(),
      'linkedDeckId': linkedDeckId,
      'plannerEventId': plannerEventId,
      'recurrenceRule': recurrenceRule,
      'attachments': attachments.map((a) => a.toMap()).toList(),
      if (attachments.isNotEmpty) ...{
        'attachmentFileName': attachments.first.fileName,
        'attachmentMimeType': attachments.first.mimeType,
        'attachmentStorageUrl': attachments.first.storageUrl,
      } else ...{
        'attachmentFileName': attachmentFileName,
        'attachmentMimeType': attachmentMimeType,
        'attachmentStorageUrl': attachmentStorageUrl,
      },
      'homeworkType': homeworkType,
      'vocabulary': vocabulary.map((e) => e.toMap()).toList(),
      'mathProblems': mathProblems.map((e) => e.toMap()).toList(),
      if (gradeHint != null) 'gradeHint': gradeHint,
      'updatedAt': Timestamp.fromDate(now),
    };
  }

  HomeworkItem copyWith({
    String? id,
    String? subject,
    String? topic,
    String? title,
    String? details,
    String? extractedText,
    String? summary,
    HomeworkTtsPreference? ttsPreference,
    DateTime? dueAt,
    HomeworkStatus? status,
    List<HomeworkSubtask>? subtasks,
    List<HomeworkStep>? steps,
    String? linkedDeckId,
    String? plannerEventId,
    String? recurrenceRule,
    String? attachmentFileName,
    String? attachmentMimeType,
    String? attachmentStorageUrl,
    List<HomeworkAttachment>? attachments,
    String? homeworkType,
    List<VocabularyEntry>? vocabulary,
    List<MathProblemEntry>? mathProblems,
    int? gradeHint,
    DateTime? updatedAt,
    bool clearDueAt = false,
  }) {
    return HomeworkItem(
      id: id ?? this.id,
      familyId: familyId,
      assignedToUserId: assignedToUserId,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      title: title ?? this.title,
      details: details ?? this.details,
      extractedText: extractedText ?? this.extractedText,
      summary: summary ?? this.summary,
      ttsPreference: ttsPreference ?? this.ttsPreference,
      dueAt: clearDueAt ? null : dueAt ?? this.dueAt,
      status: status ?? this.status,
      subtasks: subtasks ?? this.subtasks,
      steps: steps ?? this.steps,
      linkedDeckId: linkedDeckId ?? this.linkedDeckId,
      plannerEventId: plannerEventId ?? this.plannerEventId,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      source: source,
      createdByUserId: createdByUserId,
      attachmentFileName: attachmentFileName ?? this.attachmentFileName,
      attachmentMimeType: attachmentMimeType ?? this.attachmentMimeType,
      attachmentStorageUrl: attachmentStorageUrl ?? this.attachmentStorageUrl,
      attachments: attachments ?? this.attachments,
      homeworkType: homeworkType ?? this.homeworkType,
      vocabulary: vocabulary ?? this.vocabulary,
      mathProblems: mathProblems ?? this.mathProblems,
      gradeHint: gradeHint ?? this.gradeHint,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
