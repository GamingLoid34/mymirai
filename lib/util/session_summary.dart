import '../models/flashcard.dart';
import '../services/spaced_repetition.dart';

class SessionSummary {
  const SessionSummary({
    required this.total,
    required this.satDirekt,
    required this.comebackFronts,
    required this.truncated,
  });

  final int total;
  final int satDirekt; // good + easy
  final List<String> comebackFronts; // fronts för again/hard, max 5, i kortordning
  final bool truncated; // fler än 5 fanns
}

SessionSummary buildSessionSummary({
  required List<Flashcard> cards,
  required Map<String, ReviewQuality> results,
}) {
  var satDirekt = 0;
  final allComebacks = <String>[];

  for (final card in cards) {
    final quality = results[card.id];
    if (quality == null) continue;
    if (quality == ReviewQuality.good || quality == ReviewQuality.easy) {
      satDirekt++;
    } else if (quality == ReviewQuality.again || quality == ReviewQuality.hard) {
      allComebacks.add(card.front);
    }
  }

  final truncated = allComebacks.length > 5;
  final comebackFronts =
      truncated ? allComebacks.take(5).toList() : allComebacks;

  return SessionSummary(
    total: cards.length,
    satDirekt: satDirekt,
    comebackFronts: comebackFronts,
    truncated: truncated,
  );
}
