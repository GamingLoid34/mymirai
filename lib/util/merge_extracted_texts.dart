import '../models/homework_attachment.dart';
import '../models/homework_item.dart';
import 'q_and_a_heuristic.dart';

/// Sammanställer per-källtext till ett underlag för sammanfattning/TTS (v5-format).
String mergeAttachmentExtractedTexts(
  List<HomeworkAttachment> attachments,
) {
  if (attachments.isEmpty) return '';

  final parts = <String>[];
  for (var i = 0; i < attachments.length; i++) {
    final a = attachments[i];
    final t = (a.extractedText ?? '').trim();
    if (t.isEmpty) continue;
    final idx = i + 1;
    parts.add(
      '--- Källa $idx: ${a.fileName.trim().isEmpty ? 'bilaga' : a.fileName.trim()} ---\n$t',
    );
  }
  return parts.join('\n\n');
}

/// Filtrerar källor som ska användas för sammanfattning / TTS.
/// Q&A‑källor utesluts, "övrigt" utesluts; default = alla utom dessa.
String mergeListenableExtractedText(List<HomeworkAttachment> attachments) {
  final filtered = attachments
      .where((a) =>
          a.role == HomeworkAttachmentRole.summary ||
          a.role == HomeworkAttachmentRole.mixed)
      .toList();
  if (filtered.isEmpty) return '';
  return mergeAttachmentExtractedTexts(filtered);
}

/// Föreslår en roll baserat på extraherad text + filnamn.
/// Återlämnar `null` om ingen tydlig signal finns (lämna oförändrat).
HomeworkAttachmentRole? suggestRoleFor({
  required String fileName,
  required String extractedText,
}) {
  final t = extractedText.trim();
  if (t.isNotEmpty && looksLikeQAndA(t)) return HomeworkAttachmentRole.qa;

  final lower = fileName.toLowerCase();
  if (lower.contains('fragor') ||
      lower.contains('frågor') ||
      lower.contains('quiz') ||
      lower.contains('q&a') ||
      lower.contains('qa')) {
    return HomeworkAttachmentRole.qa;
  }
  if (lower.contains('sammanfattning') ||
      lower.contains('summary') ||
      lower.contains('text')) {
    return HomeworkAttachmentRole.summary;
  }
  return null;
}

/// Rekonstruerar lista från [HomeworkItem.attachments] eller äldre enkel‑URL‑fält.
List<HomeworkAttachment> attachmentsOrLegacySynthetic(HomeworkItem item) {
  if (item.attachments.isNotEmpty) return [...item.attachments];
  final url = item.attachmentStorageUrl?.trim() ?? '';
  if (url.isEmpty) return [];
  final fn = item.attachmentFileName?.trim();
  final mt = item.attachmentMimeType?.trim();
  return [
    HomeworkAttachment(
      fileName: (fn != null && fn.isNotEmpty) ? fn : 'bilaga',
      mimeType: (mt != null && mt.isNotEmpty) ? mt : 'application/octet-stream',
      storageUrl: url,
      extractedText: null,
      addedAt: item.createdAt,
    ),
  ];
}

/// Sparar extrakt för en bilaga, uppdaterar [attachments] och sammanslagen [extractedText].
HomeworkItem withAttachmentExtractApplied(
  HomeworkItem item,
  int attachmentIndex,
  String extractedText,
) {
  final trimmed = extractedText.trim();
  var rows = attachmentsOrLegacySynthetic(item);
  if (rows.isEmpty) {
    return item.copyWith(extractedText: trimmed);
  }
  if (attachmentIndex < 0 || attachmentIndex >= rows.length) {
    return item.copyWith(extractedText: trimmed);
  }
  final next = [...rows];
  final current = next[attachmentIndex];
  HomeworkAttachmentRole nextRole = current.role;
  // Auto‑gissa roll endast om den fortfarande är default ([mixed]).
  if (nextRole == HomeworkAttachmentRole.mixed) {
    final guessed = suggestRoleFor(
      fileName: current.fileName,
      extractedText: trimmed,
    );
    if (guessed != null) nextRole = guessed;
  }
  next[attachmentIndex] = current.copyWith(
    extractedText: trimmed,
    role: nextRole,
  );
  final merged = mergeAttachmentExtractedTexts(next);
  return item.copyWith(
    attachments: next,
    extractedText: merged.isEmpty ? trimmed : merged,
  );
}
