import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

const kMaxDocumentUploadBytes = 25 * 1024 * 1024;

final _allowedMime = <String>{
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/heic',
  'image/heif',
};

String _guessMimeFromFileName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return '';
}

bool isAllowedDocumentFileType(String fileName, String mimeTypeRaw) {
  final dot = fileName.toLowerCase();
  final blockedExe = dot.endsWith('.exe') ||
      dot.endsWith('.bat') ||
      dot.endsWith('.cmd') ||
      dot.endsWith('.msi');
  if (blockedExe) return false;
  final mt = mimeTypeRaw.trim().toLowerCase();
  final guessed = _guessMimeFromFileName(fileName);
  final effective = mt.isNotEmpty ? mt : guessed;
  if (!_allowedMime.contains(effective)) return false;
  return true;
}

class DocumentUploadResult {
  DocumentUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.sizeBytes,
    required this.effectiveMimeType,
  });

  final String downloadUrl;
  final String storagePath;
  final int sizeBytes;
  final String effectiveMimeType;
}

/// Läser upp till `documents/{ownerUid}/{documentId}/{fileName}`.
Future<DocumentUploadResult> uploadDocumentAttachmentBytes({
  required String ownerUid,
  required String documentId,
  required String fileName,
  required Uint8List bytes,
  String? contentTypeHint,
}) async {
  if (bytes.length > kMaxDocumentUploadBytes) {
    throw StateError('Filen är för stor (max 25 MB).');
  }
  if (bytes.isEmpty) {
    throw StateError('Filen är tom.');
  }
  final safe = fileName.replaceAll(RegExp(r'[^\w.\- \+]'), '_').trim();
  final name = safe.isEmpty ? 'fil' : safe;
  final hint = contentTypeHint?.trim().toLowerCase() ?? '';
  final guessed = _guessMimeFromFileName(name);
  final effectiveMime = hint.isNotEmpty ? hint : guessed;
  if (!isAllowedDocumentFileType(name, effectiveMime)) {
    throw StateError(
      'Ogiltigt format. Tillåt: PDF, Word (.docx), JPG, PNG, HEIC.',
    );
  }

  final authUid = FirebaseAuth.instance.currentUser?.uid;
  if (authUid == null || authUid.isEmpty) {
    throw StateError(
      'Du är inte inloggad mot Firebase Auth. Storage kräver inloggning.',
    );
  }
  if (ownerUid != authUid) {
    throw StateError(
      'Ägar-id stämmer inte med inloggad användare. Öppna appen igen efter inloggning.',
    );
  }

  final path = 'documents/$ownerUid/$documentId/$name';
  final ref = FirebaseStorage.instance.ref(path);

  await FirebaseAuth.instance.currentUser?.getIdToken(true);

  await ref.putData(
    bytes,
    SettableMetadata(
      contentType: effectiveMime.isEmpty ? null : effectiveMime,
    ),
  );
  final url = await ref.getDownloadURL();
  final fullPath = ref.fullPath;
  return DocumentUploadResult(
    downloadUrl: url,
    storagePath: fullPath,
    sizeBytes: bytes.length,
    effectiveMimeType: effectiveMime,
  );
}
