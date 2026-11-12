import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/data/local_homework_repository.dart';
import 'package:my_mirai/models/homework_item.dart';
import 'package:my_mirai/services/local_practice.dart';
import 'package:my_mirai/services/school_letter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime(2026, 11, 1);
List<HomeworkItem> extract(String text, {bool vardag = false}) =>
    suggestHomework(
      SchoolLetter(title: 'Testbrev', text: text, fromVardag: vardag),
      familyId: 'lokal',
      uid: 'elev',
      now: now,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Exempelbrevet ger tre användbara läxor och ingen biblioteksutflykt',
    () {
      final drafts = extract(exampleSchoolLetter);
      expect(drafts.map((d) => d.subject), [
        'Svenska',
        'Engelska',
        'Matematik',
      ]);
      expect(drafts.first.extractedText, contains('Skriv två meningar'));
      expect(drafts.every((d) => d.dueAt == null), isTrue);
      final vocabulary = practiceFor(drafts[1]);
      expect(drafts[1].title, isNot(contains('äpple')));
      expect(vocabulary.length, 3);
      expect(vocabulary.first.matches(' ÄPPLE '), isTrue);
      expect(vocabulary.first.matches('bok'), isFalse);
      final math = practiceFor(drafts[2]);
      expect(math.first.answer, '14');
      expect(math.last.answer, '63');
      expect(practiceFor(drafts.first).first.answer, isNull);
    },
  );
  test('Olika brev med likadan återkommande uppgift kan sparas var för sig', () {
    List<HomeworkItem> note(String id, String content) => suggestHomework(
      SchoolLetter(
        title: 'Uppgift',
        text: content,
        noteId: id,
        fromVardag: true,
      ),
      familyId: 'familj',
      uid: 'elev',
      now: now,
    );
    const task = 'Svenska: Läs nästa kapitel.';
    expect(note('v45', task).single.id, isNot(note('v46', task).single.id));
    expect(
      note('v45', task).single.id,
      note('v45', 'Ny rubrik\n$task').single.id,
    );
    expect(
      extract(
        'Veckobrev vecka 45 Engelska: Läs sidan 8. Matematik: Öva på 7:ans tabell.',
      ).length,
      2,
    );
    expect(explicitSchoolDate('Räkna ut 4/5 av 20', now), isNull);
  });
  test('Informationsbrev, skoltid och inställda läxor skapar inget', () {
    expect(
      extract(
        'Veckobrev 45\nInga matteläxor den här veckan.\nLäsning i skolan.\nPå fredag går vi till museet.',
      ),
      isEmpty,
    );
  });
  test(
    'En bestämd giltig dag kan sparas och ett oklart datum lämnas öppet',
    () {
      expect(explicitSchoolDate('Läxa till 5/11', now), DateTime(2026, 11, 5));
      expect(explicitSchoolDate('Prov 2027-01-12', now), DateTime(2027, 1, 12));
      expect(explicitSchoolDate('Prov 31/2', now), isNull);
      expect(explicitSchoolDate('Till fredag', now), isNull);
      expect(
        explicitSchoolDate('Till 7/1', DateTime(2026, 12, 27)),
        DateTime(2027, 1, 7),
      );
    },
  );
  test('Glospar under raden med förhöret följer med i övningen', () {
    final drafts = extract(
      'Engelska: Träna glosorna till torsdag.\napple - äpple\nbook = bok',
    );
    expect(drafts.length, 1);
    expect(practiceFor(drafts.single).map((s) => s.answer), ['äpple', 'bok']);
  });
  test(
    'Räkneövningar använder uppgiften, sidhänvisningar blir inget facit',
    () {
      final math = extract('Matematik: Räkna ut 4 × 6.').single;
      expect(practiceFor(math).single.answer, '24');
      expect(
        practiceFor(
          math.copyWith(extractedText: 'Räkna sidorna 12-14.'),
        ).first.answer,
        isNull,
      );
    },
  );
  test(
    'Två samtidiga importer sparar en uppsättning och behåller framsteg efter omstart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalHomeworkRepository(prefs);
      final selected = extract(exampleSchoolLetter).sublist(1);
      final results = await Future.wait([
        repo.importSelected(selected),
        repo.importSelected(selected),
      ]);
      expect(results, [2, 0]);
      final edited = selected.first.copyWith(
        title: 'Min engelska',
        status: HomeworkStatus.done,
        dueAt: DateTime(2026, 11, 4),
        steps: [const HomeworkStep(id: 'p1', label: 'Träna', done: true)],
      );
      await repo.update(edited);
      expect(
        await repo.importSelected(
          extract(exampleSchoolLetter, vardag: true).sublist(1),
        ),
        0,
      );
      await prefs.reload();
      final restored = LocalHomeworkRepository(prefs);
      final list = await restored
          .watchForFamily(familyId: 'lokal', assignedToUserId: 'elev')
          .first;
      expect(list.length, 2);
      expect(list.first.title, 'Min engelska');
      expect(list.first.status, HomeworkStatus.done);
      expect(list.first.steps.single.done, isTrue);
      expect(list.first.dueAt, DateTime(2026, 11, 4));
      expect(await restored.watchForFamily(familyId: 'annat').first, isEmpty);
    },
  );
}
