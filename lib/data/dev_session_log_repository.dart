import 'dart:async';

import '../models/study_session_log.dart';
import 'session_log_repository.dart';

class DevSessionLogRepository implements SessionLogRepository {
  final List<StudySessionLog> _logs = [];
  final _controller = StreamController<List<StudySessionLog>>.broadcast();

  @override
  Future<void> saveLog(StudySessionLog log) async {
    final entry = log.id.isNotEmpty
        ? log
        : StudySessionLog(
            id: 'dev-log-${DateTime.now().millisecondsSinceEpoch}',
            homeworkId: log.homeworkId,
            deckId: log.deckId,
            userId: log.userId,
            completedAt: log.completedAt,
            totalCards: log.totalCards,
            correctCards: log.correctCards,
            incorrectCards: log.incorrectCards,
            missedFronts: log.missedFronts,
            durationSeconds: log.durationSeconds,
            mode: log.mode,
          );
    _logs.insert(0, entry);
    _controller.add(List.unmodifiable(_logs));
  }

  @override
  Stream<List<StudySessionLog>> watchLogsForHomework(String homeworkId) {
    return _controller.stream.map(
      (list) => list.where((l) => l.homeworkId == homeworkId).toList(),
    );
  }

  @override
  Future<StudySessionLog?> getLatestLogForHomework(String homeworkId) async {
    for (final l in _logs) {
      if (l.homeworkId == homeworkId) return l;
    }
    return null;
  }
}
