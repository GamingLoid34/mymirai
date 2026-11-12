import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Laddar upp bilaga till `families/{familyId}/homework/{homeworkId}/{fileName}`.
Future<String> uploadHomeworkAttachmentBytes({
  required String familyId,
  required String homeworkId,
  required String fileName,
  required Uint8List bytes,
  String? contentType,
}) async {
  final safe = fileName.replaceAll(RegExp(r'[^\w.\- \+]'), '_').trim();
  final name = safe.isEmpty ? 'fil' : safe;
  final prefixed = '${DateTime.now().millisecondsSinceEpoch}_$name';
  final ref = FirebaseStorage.instance.ref(
    'families/$familyId/homework/$homeworkId/$prefixed',
  );
  await ref.putData(
    bytes,
    SettableMetadata(contentType: contentType),
  );
  return ref.getDownloadURL();
}
