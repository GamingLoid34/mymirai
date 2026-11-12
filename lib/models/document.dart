import 'package:cloud_firestore/cloud_firestore.dart';

/// Bilaga för vuxen-dokument (Storage under `documents/{ownerUid}/{docId}/…`).
class DocumentAttachment {
  const DocumentAttachment({
    required this.storagePath,
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String storagePath;
  final String fileName;
  final int sizeBytes;
  final String mimeType;

  Map<String, dynamic> toMap() => {
        'storagePath': storagePath,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'mimeType': mimeType,
      };

  static DocumentAttachment? tryParse(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final path = raw['storagePath'] as String? ?? '';
    final name = raw['fileName'] as String? ?? '';
    final mime = raw['mimeType'] as String? ?? '';
    final sz = (raw['sizeBytes'] as num?)?.toInt();
    if (path.isEmpty || name.isEmpty || mime.isEmpty || sz == null) return null;
    return DocumentAttachment(
      storagePath: path,
      fileName: name,
      sizeBytes: sz,
      mimeType: mime,
    );
  }
}

class DocumentHighlight {
  const DocumentHighlight({
    required this.startOffset,
    required this.endOffset,
    required this.color,
    this.note,
  });

  final int startOffset;
  final int endOffset;
  final String color;
  final String? note;

  Map<String, dynamic> toMap() => {
        'startOffset': startOffset,
        'endOffset': endOffset,
        'color': color,
        'note': note,
      };

  static DocumentHighlight fromMap(Map<String, dynamic> data) {
    return DocumentHighlight(
      startOffset: (data['startOffset'] as num?)?.toInt() ?? 0,
      endOffset: (data['endOffset'] as num?)?.toInt() ?? 0,
      color: data['color'] as String? ?? 'yellow',
      note: data['note'] as String?,
    );
  }
}

class UserDocument {
  const UserDocument({
    required this.id,
    required this.ownerUid,
    required this.title,
    this.summary,
    this.extractedText,
    this.audioCachedAt,
    this.audioStoragePath,
    this.sourceUrl,
    this.attachment,
    this.attachmentStorageUrl,
    required this.sourceType,
    this.highlights = const [],
    this.createdAt,
    this.updatedAt,
    this.lastReadAt,
    this.readingProgress = 0.0,
    this.userNotes,
  });

  final String id;
  final String ownerUid;
  final String title;
  final String? summary;
  final String? extractedText;
  final DateTime? audioCachedAt;

  /// Storage-sökväg till cachad ElevenLabs-uppläsning (VO-01).
  final String? audioStoragePath;
  final String? sourceUrl;
  final DocumentAttachment? attachment;
  final String? attachmentStorageUrl;
  final String sourceType;
  final List<DocumentHighlight> highlights;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastReadAt;
  final double readingProgress;

  /// Fritextanteckningar (Chunk R), synliga endast för ägaren.
  final String? userNotes;

  static UserDocument fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final hRaw = data['highlights'];
    final highlights = <DocumentHighlight>[];
    if (hRaw is List) {
      for (final e in hRaw) {
        if (e is Map<String, dynamic>) {
          highlights.add(DocumentHighlight.fromMap(e));
        }
      }
    }
    return UserDocument(
      id: doc.id,
      ownerUid: data['ownerUid'] as String? ?? '',
      title: data['title'] as String? ?? '',
      summary: data['summary'] as String?,
      extractedText: data['extractedText'] as String?,
      audioCachedAt: _asDate(data['audioCachedAt']),
      audioStoragePath: data['audioStoragePath'] as String?,
      sourceUrl: data['sourceUrl'] as String?,
      attachment: DocumentAttachment.tryParse(data['attachment']),
      attachmentStorageUrl: data['attachmentStorageUrl'] as String?,
      sourceType: data['sourceType'] as String? ?? 'text',
      highlights: highlights,
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      lastReadAt: _asDate(data['lastReadAt']),
      readingProgress: (data['readingProgress'] as num?)?.toDouble() ?? 0.0,
      userNotes: data['userNotes'] as String?,
    );
  }

  Map<String, dynamic> toCreateMap(DateTime now) => {
        'ownerUid': ownerUid,
        'title': title,
        'summary': summary,
        'extractedText': extractedText,
        'audioCachedAt': audioCachedAt != null ? Timestamp.fromDate(audioCachedAt!) : null,
        'audioStoragePath': audioStoragePath,
        'sourceUrl': sourceUrl,
        'attachment': attachment?.toMap(),
        'attachmentStorageUrl': attachmentStorageUrl,
        'sourceType': sourceType,
        'highlights': highlights.map((h) => h.toMap()).toList(),
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'lastReadAt': lastReadAt != null ? Timestamp.fromDate(lastReadAt!) : null,
        'readingProgress': readingProgress,
        'userNotes': userNotes,
      };

  Map<String, dynamic> toUpdateMap(DateTime now) => {
        'ownerUid': ownerUid,
        'title': title,
        'summary': summary,
        'extractedText': extractedText,
        'audioCachedAt': audioCachedAt != null ? Timestamp.fromDate(audioCachedAt!) : null,
        'audioStoragePath': audioStoragePath,
        'sourceUrl': sourceUrl,
        'attachment': attachment?.toMap(),
        'attachmentStorageUrl': attachmentStorageUrl,
        'sourceType': sourceType,
        'highlights': highlights.map((h) => h.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(now),
        'lastReadAt': lastReadAt != null ? Timestamp.fromDate(lastReadAt!) : null,
        'readingProgress': readingProgress,
        'userNotes': userNotes,
      };

  UserDocument copyWith({
    String? id,
    String? title,
    String? summary,
    bool clearSummary = false,
    String? extractedText,
    bool clearExtractedText = false,
    DateTime? audioCachedAt,
    String? audioStoragePath,
    String? sourceUrl,
    bool clearSourceUrl = false,
    DocumentAttachment? attachment,
    bool clearAttachment = false,
    String? attachmentStorageUrl,
    bool clearAttachmentStorageUrl = false,
    String? sourceType,
    List<DocumentHighlight>? highlights,
    DateTime? lastReadAt,
    double? readingProgress,
    String? userNotes,
    bool clearUserNotes = false,
  }) {
    return UserDocument(
      id: id ?? this.id,
      ownerUid: ownerUid,
      title: title ?? this.title,
      summary: clearSummary ? null : (summary ?? this.summary),
      extractedText: clearExtractedText
          ? null
          : (extractedText ?? this.extractedText),
      audioCachedAt: audioCachedAt ?? this.audioCachedAt,
      audioStoragePath: audioStoragePath ?? this.audioStoragePath,
      sourceUrl: clearSourceUrl ? null : (sourceUrl ?? this.sourceUrl),
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
      attachmentStorageUrl: clearAttachmentStorageUrl
          ? null
          : (attachmentStorageUrl ?? this.attachmentStorageUrl),
      sourceType: sourceType ?? this.sourceType,
      highlights: highlights ?? this.highlights,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      readingProgress: readingProgress ?? this.readingProgress,
      userNotes: clearUserNotes ? null : (userNotes ?? this.userNotes),
    );
  }
}

DateTime? _asDate(dynamic value) => value is Timestamp ? value.toDate() : null;
