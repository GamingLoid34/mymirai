import 'package:cloud_firestore/cloud_firestore.dart';

/// Vad bilagan _används till_ i appen.
///
/// * [summary] — sammanfattning eller löptext att lyssna på (TTS).
/// * [qa]      — frågor & svar; inte för uppläsning, mål för flashcards.
/// * [mixed]   — innehåller både; används för båda flödena (default).
/// * [other]   — bild på arbetsbok eller liknande; ingen särskild roll.
enum HomeworkAttachmentRole {
  summary,
  qa,
  mixed,
  other;

  String get firestoreValue => name;

  static HomeworkAttachmentRole fromFirestore(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'summary':
        return HomeworkAttachmentRole.summary;
      case 'qa':
      case 'questions':
        return HomeworkAttachmentRole.qa;
      case 'other':
        return HomeworkAttachmentRole.other;
      case 'mixed':
      default:
        return HomeworkAttachmentRole.mixed;
    }
  }

  /// UI-etikett (Svenska).
  String get labelSv {
    switch (this) {
      case HomeworkAttachmentRole.summary:
        return 'Sammanfattning';
      case HomeworkAttachmentRole.qa:
        return 'Frågor & svar';
      case HomeworkAttachmentRole.mixed:
        return 'Blandat';
      case HomeworkAttachmentRole.other:
        return 'Övrigt';
    }
  }
}

/// Bilaga eller sida kopplad till en läxa (roadmap v5 — flera källor).
class HomeworkAttachment {
  const HomeworkAttachment({
    required this.fileName,
    required this.mimeType,
    required this.storageUrl,
    this.extractedText,
    required this.addedAt,
    this.role = HomeworkAttachmentRole.mixed,
  });

  final String fileName;
  final String mimeType;
  final String storageUrl;
  final String? extractedText;
  final DateTime addedAt;
  final HomeworkAttachmentRole role;

  Map<String, dynamic> toMap() => {
        'fileName': fileName,
        'mimeType': mimeType,
        'storageUrl': storageUrl,
        'extractedText': extractedText,
        'addedAt': Timestamp.fromDate(addedAt),
        'role': role.firestoreValue,
      };

  static HomeworkAttachment fromMap(Map<String, dynamic> m) {
    final rawAdded = m['addedAt'];
    return HomeworkAttachment(
      fileName: (m['fileName'] as String?)?.trim() ?? 'fil',
      mimeType: (m['mimeType'] as String?)?.trim().isNotEmpty == true
          ? (m['mimeType'] as String).trim()
          : 'application/octet-stream',
      storageUrl: (m['storageUrl'] as String?)?.trim() ?? '',
      extractedText: (m['extractedText'] as String?)?.trim().isEmpty == true
          ? null
          : (m['extractedText'] as String?)?.trim(),
      addedAt: rawAdded is Timestamp
          ? rawAdded.toDate()
          : DateTime.now(),
      role: HomeworkAttachmentRole.fromFirestore(m['role'] as String?),
    );
  }

  HomeworkAttachment copyWith({
    String? fileName,
    String? mimeType,
    String? storageUrl,
    String? extractedText,
    DateTime? addedAt,
    HomeworkAttachmentRole? role,
  }) {
    return HomeworkAttachment(
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      storageUrl: storageUrl ?? this.storageUrl,
      extractedText: extractedText ?? this.extractedText,
      addedAt: addedAt ?? this.addedAt,
      role: role ?? this.role,
    );
  }
}
