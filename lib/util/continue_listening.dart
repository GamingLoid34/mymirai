import '../models/document.dart';

/// Clampar `position / duration` till 0.0–1.0. Returnerar 0.0 om `duration` är 0.
double computeReadingProgress({
  required Duration position,
  required Duration duration,
}) {
  if (duration.inMilliseconds <= 0) return 0.0;
  final v = position.inMilliseconds / duration.inMilliseconds;
  if (v < 0) return 0.0;
  if (v > 1) return 1.0;
  return v;
}

/// Dokumentet att visa i "Fortsätt lyssna"-kortet: senast `lastReadAt` bland
/// dem med `0.02 < readingProgress < 0.97`. `null` om inget kvalificerar.
UserDocument? pickContinueListening(List<UserDocument> docs) {
  UserDocument? best;
  for (final d in docs) {
    if (d.readingProgress <= 0.02 || d.readingProgress >= 0.97) continue;
    final lastRead = d.lastReadAt;
    if (lastRead == null) continue;
    final bestLastRead = best?.lastReadAt;
    if (best == null || bestLastRead == null || lastRead.isAfter(bestLastRead)) {
      best = d;
    }
  }
  return best;
}
