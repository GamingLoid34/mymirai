import '../models/study_session_log.dart';

/// Repository för att spara och läsa loggar från genomförda förhör (AP8).
abstract class SessionLogRepository {
  Future<void> saveLog(StudySessionLog log);
  Stream<List<StudySessionLog>> watchLogsForHomework(String homeworkId);
  Future<StudySessionLog?> getLatestLogForHomework(String homeworkId);
}
