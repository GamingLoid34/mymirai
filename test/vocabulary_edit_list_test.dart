import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/models/vocabulary_entry.dart';
import 'package:my_mirai/widgets/vocabulary_edit_list.dart';

void main() {
  testWidgets('VocabularyEditList displays entries and handles editing and saving',
      (tester) async {
    List<VocabularyEntry>? saved;
    var cancelled = false;

    final initial = [
      const VocabularyEntry(term: 'cat', translation: 'katt'),
      const VocabularyEntry(term: 'dog', translation: 'hund'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VocabularyEditList(
            initialEntries: initial,
            onSaved: (res) => saved = res,
            onCancel: () => cancelled = true,
          ),
        ),
      ),
    );

    expect(find.text('cat'), findsOneWidget);
    expect(find.text('katt'), findsOneWidget);
    expect(find.text('dog'), findsOneWidget);
    expect(find.text('hund'), findsOneWidget);

    // Add entry
    await tester.tap(find.text('Lägg till glosa'));
    await tester.pump();

    // Now 3 items
    expect(find.text('3 st'), findsOneWidget);

    // Save
    await tester.tap(find.text('Spara glosor'));
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!.length, 2); // empty 3rd entry filtered out
    expect(saved![0].term, 'cat');
    expect(saved![1].term, 'dog');

    // Test cancel
    await tester.tap(find.text('Avbryt'));
    await tester.pump();
    expect(cancelled, isTrue);
  });
}
