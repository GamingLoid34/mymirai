import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/data/local_homework_repository.dart';
import 'package:my_mirai/models/homework_item.dart';
import 'package:my_mirai/screens/school_letter_import_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Granska, ändra och spara bara de markerade läxorna', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalHomeworkRepository(
      await SharedPreferences.getInstance(),
    );
    final observations = <List<HomeworkItem>>[];
    final sub = repository
        .watchForFamily(familyId: 'lokal')
        .listen(observations.add);
    addTearDown(sub.cancel);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Veckobrev'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SchoolLetterImportScreen(
                    repository: repository,
                    familyId: 'lokal',
                    uid: 'barn',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Veckobrev'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prova med ett exempelbrev'));
    await tester.pumpAndSettle();
    expect(find.text('Spara valda (3)'), findsOneWidget);
    expect(observations.last, isEmpty);
    await tester.tap(find.byType(Checkbox).first);
    await tester.tap(find.byTooltip('Ändra läxan').at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Veckans engelska');
    await tester.ensureVisible(find.text('Använd förslaget'));
    await tester.tap(find.text('Använd förslaget'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Spara valda (2)'));
    await tester.tap(find.text('Spara valda (2)'));
    await tester.pumpAndSettle();
    expect(find.text('2 nya läxor har sparats.'), findsOneWidget);
    final saved = observations.last;
    expect(saved.length, 2);
    expect(saved.any((h) => h.title == 'Veckans engelska'), isTrue);
    expect(saved.any((h) => h.subject == 'Svenska'), isFalse);
  });
}
