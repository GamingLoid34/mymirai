import '../models/homework_item.dart';

/// Härleder 2–4 småsteg för en läxa lokalt (ingen AI).
///
/// Nedbrytning i tydliga, korta steg är ADHD-mönstret nr 1 — barnet ska
/// alltid se ETT steg att göra just nu, inte en hel läxa på en gång.
List<HomeworkStep> deriveSteps(HomeworkItem h) {
  final steps = <HomeworkStep>[];
  var i = 0;
  String nextId() => 's${i++}';

  if (h.isVocabularyHomework) {
    steps.add(HomeworkStep(id: nextId(), label: 'Lyssna på orden'));
    steps.add(HomeworkStep(id: nextId(), label: 'Träna glosorna'));
    steps.add(HomeworkStep(id: nextId(), label: 'Förhör dig själv'));
  } else if (h.isMathHomework) {
    steps.add(HomeworkStep(id: nextId(), label: 'Titta på uppgifterna'));
    steps.add(HomeworkStep(id: nextId(), label: 'Räkna'));
    steps.add(HomeworkStep(id: nextId(), label: 'Kolla dina svar'));
  } else {
    final hasText = (h.extractedText ?? h.summary ?? '').trim().isNotEmpty;
    if (hasText) {
      steps.add(HomeworkStep(id: nextId(), label: 'Lyssna på läxan'));
    }
    final hasDeck = (h.linkedDeckId ?? '').trim().isNotEmpty;
    if (hasDeck) {
      steps.add(HomeworkStep(id: nextId(), label: 'Träna korten'));
    }
    steps.add(HomeworkStep(id: nextId(), label: 'Gör förhöret'));
  }

  return steps;
}
