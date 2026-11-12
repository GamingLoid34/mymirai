import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/models/homework_item.dart';
import 'package:my_mirai/util/subject_suggestions.dart';

void main() {
  test('mergedSubjectOptions includes standard + family subjects', () {
    final opts = mergedSubjectOptions([
      HomeworkItem(
        id: '1',
        familyId: 'f',
        assignedToUserId: 'u',
        subject: 'Hemkunskap',
        title: 'T',
        dueAt: null,
        status: HomeworkStatus.todo,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      HomeworkItem(
        id: '2',
        familyId: 'f',
        assignedToUserId: 'u',
        subject: 'Ovanlig kod',
        title: 'T2',
        dueAt: null,
        status: HomeworkStatus.todo,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ]);
    expect(opts.contains('Matematik'), isTrue);
    expect(opts.contains('Hemkunskap'), isTrue);
    expect(opts.contains('Ovanlig kod'), isTrue);
    final sorted = [...opts]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(opts, orderedEquals(sorted));
  });
}
