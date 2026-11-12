import '../models/homework_item.dart';

abstract class HomeworkRepository {
  Stream<List<HomeworkItem>> watchForFamily({
    required String familyId,
    String? assignedToUserId,
  });

  Future<String> create(HomeworkItem draft);

  Future<void> update(HomeworkItem item);

  Future<void> delete(String homeworkId);
}
