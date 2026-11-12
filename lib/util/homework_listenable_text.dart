import '../models/homework_attachment.dart';
import '../models/homework_item.dart';
import 'merge_extracted_texts.dart';

String? listenableHomeworkText(HomeworkItem h) {
  if (h.isVocabularyHomework && h.vocabulary.isNotEmpty) {
    return h.vocabulary
        .map((e) => '${e.term}. ${e.translation}.')
        .join('\n\n');
  }
  final sum = h.summary?.trim();
  if (sum != null && sum.isNotEmpty) return sum;
  // Föredra "summary"/"mixed" källor om någon källa är märkt som [qa].
  final atts = attachmentsOrLegacySynthetic(h);
  if (atts.any((a) => a.role == HomeworkAttachmentRole.qa)) {
    final filtered = mergeListenableExtractedText(atts).trim();
    if (filtered.isNotEmpty) return filtered;
    return null;
  }
  final ext = h.extractedText?.trim();
  if (ext != null && ext.isNotEmpty) return ext;
  return null;
}

String listenableHomeworkLabel(HomeworkItem h) {
  if (listenableHomeworkText(h) == null) {
    return 'Lägg till text eller sammanfattning först';
  }
  final hasSummary = h.summary != null && h.summary!.trim().isNotEmpty;
  final hasQaOnlySource = attachmentsOrLegacySynthetic(h).any(
    (a) => a.role == HomeworkAttachmentRole.qa,
  );
  if (hasSummary) return 'Lyssna (sammanfattning)';
  if (hasQaOnlySource) return 'Lyssna (utan frågor & svar-källor)';
  return 'Lyssna (hela texten)';
}
