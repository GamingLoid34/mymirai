import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/homework_item.dart';

class PracticeStep {
  const PracticeStep(this.prompt, this.hint, [this.answer]);
  final String prompt, hint;
  final String? answer;
  String get id =>
      sha256.convert(utf8.encode('$prompt\n${answer ?? ''}')).toString();
  bool matches(String value) =>
      answer != null && _clean(value) == _clean(answer!);
  String _clean(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

List<PracticeStep> practiceFor(HomeworkItem item) {
  final material = (item.extractedText ?? '').trim();
  final text = material.isEmpty ? item.title : material;
  final vocab = <String, String>{
    for (final v in item.vocabulary) v.term: v.translation,
  };
  final isLanguage = [
    'engelska',
    'spanska',
    'tyska',
    'franska',
  ].contains(item.subject.toLowerCase());
  if (isLanguage ||
      item.isVocabularyHomework ||
      text.toLowerCase().contains('glos')) {
    final pair = RegExp(
      r"^([\p{L}][\p{L} '’-]{0,45}?)\s*(?:=|\s[-–]\s)\s*([\p{L}][\p{L} '’-]{0,45})[.!]?$",
      unicode: true,
    );
    for (final part in text.split(RegExp(r'[:,;\n]'))) {
      final match = pair.firstMatch(part.trim());
      if (match != null) vocab[match[1]!.trim()] = match[2]!.trim();
    }
  }
  if (vocab.isNotEmpty) {
    return [
      for (final e in vocab.entries)
        PracticeStep(
          'Vad betyder ”${e.key}”?',
          'Ordet börjar på ”${String.fromCharCode(e.value.runes.first)}”. Säg det högt innan du skriver.',
          e.value,
        ),
    ];
  }
  final math =
      item.isMathHomework ||
      item.subject.toLowerCase().startsWith('mat') ||
      RegExp(r'\btabell', caseSensitive: false).hasMatch(text);
  if (math) {
    final steps = <PracticeStep>[];
    final table =
        RegExp(
          r'\b(1[0-2]|[1-9])\s*(?::?ans?|:s)\s*tabell',
          caseSensitive: false,
        ).firstMatch(text) ??
        RegExp(
          r'(?:multiplikations)?tabell(?:en)?\s+(1[0-2]|[1-9])\b',
          caseSensitive: false,
        ).firstMatch(text);
    if (table != null) {
      final n = int.parse(table[1]!);
      for (final b in [2, 5, 7, 9]) {
        steps.add(
          PracticeStep(
            'Vad är $b × $n?',
            'Räkna $b hopp med $n i varje hopp.',
            '${b * n}',
          ),
        );
      }
    }
    final expression = RegExp(
      r'^(?:(?:räkna(?: ut)?|beräkna|vad är)\s+)?(\d{1,4})\s*([+×x*−÷-]|\s/\s)\s*(\d{1,4})\s*[=?.!]*$',
      caseSensitive: false,
    );
    for (final part in [
      text,
      ...item.mathProblems.map((p) => p.originalText),
    ].expand((s) => s.split(RegExp(r'[:,;\n]|\s+och\s+')))) {
      final m = expression.firstMatch(part.trim());
      if (m == null) continue;
      final a = int.parse(m[1]!), b = int.parse(m[3]!);
      final op = m[2]!.trim().toLowerCase();
      if ((op == '÷' || op == '/') && (b == 0 || a % b != 0)) continue;
      final (answer, hint) = switch (op) {
        '+' => (a + b, 'Lägg först ihop tiotalen, sedan entalen.'),
        '-' || '−' => (a - b, 'Börja vid $a och hoppa $b steg bakåt.'),
        '÷' || '/' => (a ~/ b, 'Vilket tal gånger $b blir $a?'),
        _ => (
          a * b,
          'Dela upp $a i två mindre tal och multiplicera delarna med $b.',
        ),
      };
      steps.add(PracticeStep('Vad är $a $op $b?', hint, '$answer'));
    }
    if (steps.isNotEmpty) return steps;
    return const [
      PracticeStep(
        'Vilka tal och vilken fråga har du fått?',
        'Leta upp den första uppgiften i boken. Stryk under vad du ska räkna ut.',
      ),
      PracticeStep(
        'Räkna ett tal i taget.',
        'Rita en bild eller skriv mellanleden. Förklara varför du valde räknesättet.',
      ),
      PracticeStep(
        'Hur kan du kontrollera ditt svar?',
        'Uppskatta svaret eller räkna baklänges. Jämför med din uträkning.',
      ),
    ];
  }
  if (isLanguage || text.toLowerCase().contains('glos')) {
    return const [
      PracticeStep(
        'Läs upp veckans ord.',
        'Hitta glosorna i ditt material. Säg ett ord och dess översättning högt.',
      ),
      PracticeStep(
        'Vilka ord minns du utan att titta?',
        'Täck över översättningen, säg den själv och jämför med boken.',
      ),
      PracticeStep(
        'Använd ett av orden i en mening.',
        'Välj ett svårt ord. Läs meningen högt och kontrollera ordet igen.',
      ),
    ];
  }
  return const [
    PracticeStep(
      'Vad ber läraren dig att göra?',
      'Leta efter ord som ”läs”, ”skriv” eller ”förklara”. Säg uppgiften med egna ord.',
    ),
    PracticeStep(
      'Gör första delen och återberätta den.',
      'Läs ett stycke eller gör en deluppgift. Lägg undan materialet och berätta vad du minns.',
    ),
    PracticeStep(
      'Kan du förklara det för någon annan?',
      'Ge ett exempel. Jämför med materialet och kolla att du gjort allt läraren bad om.',
    ),
  ];
}
