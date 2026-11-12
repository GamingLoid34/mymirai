import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/models/homework_item.dart';
import 'package:my_mirai/util/homework_steps.dart';

HomeworkItem _hw({
  String homeworkType = 'text',
  String? extractedText,
  String? summary,
  String? linkedDeckId,
}) {
  final now = DateTime(2026, 5, 1);
  return HomeworkItem(
    id: 'h1',
    familyId: 'f1',
    assignedToUserId: 'u1',
    subject: 'Svenska',
    title: 'Läxa',
    status: HomeworkStatus.todo,
    homeworkType: homeworkType,
    extractedText: extractedText,
    summary: summary,
    linkedDeckId: linkedDeckId,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('vocabulary homework gets three fixed steps', () {
    final steps = deriveSteps(_hw(homeworkType: 'vocabulary'));
    expect(steps.map((s) => s.label), [
      'Lyssna på orden',
      'Träna glosorna',
      'Förhör dig själv',
    ]);
  });

  test('math homework gets three fixed steps', () {
    final steps = deriveSteps(_hw(homeworkType: 'math'));
    expect(steps.map((s) => s.label), [
      'Titta på uppgifterna',
      'Räkna',
      'Kolla dina svar',
    ]);
  });

  test('text homework with extracted text and no deck', () {
    final steps = deriveSteps(_hw(extractedText: 'Något att läsa'));
    expect(steps.map((s) => s.label), [
      'Lyssna på läxan',
      'Gör förhöret',
    ]);
  });

  test('text homework with extracted text and linked deck', () {
    final steps = deriveSteps(
      _hw(extractedText: 'Något att läsa', linkedDeckId: 'deck1'),
    );
    expect(steps.map((s) => s.label), [
      'Lyssna på läxan',
      'Träna korten',
      'Gör förhöret',
    ]);
  });

  test('text homework without any listenable text or deck falls back to only förhöret', () {
    final steps = deriveSteps(_hw());
    expect(steps.map((s) => s.label), ['Gör förhöret']);
  });

  test('steps start undone with stable unique ids', () {
    final steps = deriveSteps(_hw(homeworkType: 'vocabulary'));
    expect(steps.every((s) => !s.done), isTrue);
    expect(steps.map((s) => s.id).toSet().length, steps.length);
  });
}
