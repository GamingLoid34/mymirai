import '../models/document.dart';

/// Bygger kön för "Spela upp oläst": alla dokument med `readingProgress < 0.97`
/// (finns text/sammanfattning att lyssna på), nyast först (`updatedAt`).
List<UserDocument> buildListeningQueue(List<UserDocument> docs) {
  final eligible = docs.where((d) {
    if (d.readingProgress >= 0.97) return false;
    final hasListenable = (d.summary ?? d.extractedText ?? '').trim().isNotEmpty;
    return hasListenable;
  }).toList();

  eligible.sort((a, b) {
    final au = a.updatedAt;
    final bu = b.updatedAt;
    if (au == null && bu == null) return 0;
    if (au == null) return 1;
    if (bu == null) return -1;
    return bu.compareTo(au);
  });
  return eligible;
}
