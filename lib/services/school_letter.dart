import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/homework_item.dart';

const exampleSchoolLetter = '''Veckobrev från årskurs 4
På onsdag går vi till biblioteket.

Svenska: Läs kapitel 3 hemma till fredag. Skriv två meningar om huvudpersonen.
Engelska: Träna glosorna till torsdag: apple = äpple, book = bok, chair = stol.
Matematik: Öva på 7:ans tabell till fredag.''';

class SchoolLetter {
  const SchoolLetter({
    required this.title,
    required this.text,
    this.publishedAt,
    this.noteId,
    this.fromVardag = false,
  });
  final String title;
  final String text;
  final DateTime? publishedAt;
  final String? noteId;
  final bool fromVardag;
}

String _normalized(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

final _subjects = <String, RegExp>{
  'Matematik': RegExp(
    r'\b(matematik\w*|matte\w*|multiplikation\w*|tabell\w*|räkna)\b',
    caseSensitive: false,
  ),
  'Engelska': RegExp(r'\b(engelsk\w*|english)\b', caseSensitive: false),
  'Svenska': RegExp(
    r'\b(svensk\w*|läsläx\w*|läsförståelse\w*|läsbok\w*)\b',
    caseSensitive: false,
  ),
  for (final name in [
    'Spanska',
    'Tyska',
    'Franska',
    'Historia',
    'Geografi',
    'Biologi',
    'Fysik',
    'Kemi',
    'Teknik',
    'Musik',
    'Idrott',
    'SO',
    'NO',
  ])
    name: RegExp('\\b$name\\b', caseSensitive: false),
};
final _assignment = RegExp(
  r'läx|(?:^|[^\p{L}\p{N}])(glos\w*|hemuppgift\w*|hemma|(?:matte|glos|läs|ämnes)?prov(?:et)?|förhör\w*|inlämning\w*|läs|skriv|räkna|öva|träna|repetera|plugga|lös|lär er|gör klart|lämna in)\b',
  caseSensitive: false,
  unicode: true,
);
final _noHomework = RegExp(
  r'\b(?:ingen|inget|inga|inte (?:någon|några))\s+(?:(?:nya|fler)\s+)?(?:\w*läx\w*|\w*prov|förhör|glosor)|läxfri|\bslipper\b.*läx|läx\w*\s+(?:utgår|inställd)',
  caseSensitive: false,
);
final _schoolOnly = RegExp(
  r'\b(?:i skolan|på lektion(?:en|erna)|på skoltid)\b',
  caseSensitive: false,
);

String _subjectOf(String line) {
  for (final e in _subjects.entries) {
    if (e.value.hasMatch(line)) return e.key;
  }
  return '';
}

DateTime? explicitSchoolDate(String text, DateTime reference) {
  final iso = RegExp(r'\b(20\d\d)-(\d\d)-(\d\d)\b').firstMatch(text);
  final short = RegExp(
    r'\b(\d{1,2})/(\d{1,2})(?:/(20\d\d))?\b',
  ).firstMatch(text);
  if (iso == null) {
    if (short == null) return null;
    final before = text.substring(0, short.start).trimRight();
    // T.ex. 4/5 i en matteuppgift eller på en sida är inte en deadline.
    if (before.isNotEmpty &&
        !RegExp(
          r'(?:till|senast|den|prov|förhör|inlämning|dag(?:en)?)\s*[:(]?$',
          caseSensitive: false,
        ).hasMatch(before)) {
      return null;
    }
  }
  final d = int.parse(iso?.group(3) ?? short!.group(1)!);
  final m = int.parse(iso?.group(2) ?? short!.group(2)!);
  final explicitYear = iso?.group(1) ?? short?.group(3);
  var year = int.tryParse(explicitYear ?? '') ?? reference.year;
  if (explicitYear == null && reference.month == 12 && m == 1) year++;
  if (explicitYear == null && reference.month == 1 && m == 12) year--;
  final date = DateTime(year, m, d);
  return date.day == d && date.month == m ? date : null;
}

String schoolDraftId(
  SchoolLetter letter,
  String task,
  String familyId,
  String uid,
) {
  final key = jsonEncode([
    familyId,
    uid,
    letter.noteId ?? _normalized(letter.text),
    _normalized(task),
  ]);
  return 'brev-${sha256.convert(utf8.encode(key))}';
}

List<HomeworkItem> suggestHomework(
  SchoolLetter letter, {
  required String familyId,
  required String uid,
  required DateTime now,
}) {
  final results = <HomeworkItem>[];
  final seen = <String>{};
  var subjectHeading = '';
  var homeworkSection = false;
  final chunks = letter.text
      .replaceAll('\r', '\n')
      .replaceAllMapped(
        RegExp(
          r'\s+(?=(?:svenska|engelska|matematik|matte|spanska|tyska|franska|SO|NO):)',
          caseSensitive: false,
        ),
        (_) => '\n',
      )
      .split(RegExp(r'\n|(?<=[.!?])\s+(?=[A-ZÅÄÖ])|\s+[•●]\s*'));
  for (var line in chunks) {
    line = line.replaceFirst(RegExp(r'^\s*[-–•*]+\s*'), '').trim();
    if (line.isEmpty) continue;
    final stripped = line.replaceFirst(RegExp(r'[:.!]$'), '').trim();
    if (RegExp(
      r'^(?:veckans |kommande )?(?:läxor|hemuppgifter)(?:\s+v\.?\s*\d+)?$',
      caseSensitive: false,
    ).hasMatch(stripped)) {
      homeworkSection = true;
      subjectHeading = '';
      continue;
    }
    final explicitSubject = _subjectOf(line);
    if (explicitSubject.isNotEmpty &&
        RegExp(r'^[\p{L}]+:?$', unicode: true).hasMatch(line)) {
      subjectHeading = explicitSubject;
      continue;
    }
    if (_noHomework.hasMatch(line) ||
        (_schoolOnly.hasMatch(line) &&
            !RegExp(
              r'läx|hemma|prov|inlämning|lämna in',
              caseSensitive: false,
            ).hasMatch(line)) ||
        RegExp(
          r'^(?:nyhet|veckobrev|information|övrigt|kalendarium|viktiga datum|trevlig helg|hälsningar|vänliga hälsningar)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
      homeworkSection = false;
      subjectHeading = '';
      continue;
    }
    final pairLine = RegExp(
      r'^[\p{L} ]+\s(?:=|[-–])\s[\p{L} ]+[.!]?$',
      unicode: true,
    ).hasMatch(line);
    final startsTask =
        _assignment.hasMatch(line) ||
        (homeworkSection &&
            (explicitSubject.isNotEmpty || subjectHeading.isNotEmpty));
    if (pairLine &&
        results.isNotEmpty &&
        results.last.extractedText!.toLowerCase().contains('glos')) {
      final previous = results.removeLast();
      results.add(
        previous.copyWith(extractedText: '${previous.extractedText}\n$line'),
      );
      continue;
    }
    if (!startsTask) continue;
    final sourceText = line;
    var subject = explicitSubject.isEmpty ? subjectHeading : explicitSubject;
    if (subject.isEmpty &&
        RegExp(r'^läs\b', caseSensitive: false).hasMatch(line)) {
      subject = 'Svenska';
    }
    if (explicitSubject.isEmpty &&
        results.isNotEmpty &&
        RegExp(
          r'^(?:svara|skriv|berätta)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
      final previous = results.removeLast();
      results.add(
        previous.copyWith(extractedText: '${previous.extractedText} $line'),
      );
      continue;
    }
    if (explicitSubject.isNotEmpty) subjectHeading = explicitSubject;
    final prefix = line.indexOf(':');
    if (prefix > 0 &&
        prefix < 22 &&
        _subjectOf(line.substring(0, prefix)).isNotEmpty) {
      line = line.substring(prefix + 1).trim();
    }
    if (line.isEmpty) continue;
    // Håll glosornas facit i materialet när eleven öppnar övningen.
    if (RegExp(
          r'[\p{L}]\s*(?:=|\s[-–]\s)\s*[\p{L}]',
          unicode: true,
        ).hasMatch(line) &&
        (sourceText.toLowerCase().contains('glos') ||
            ['Engelska', 'Spanska', 'Tyska', 'Franska'].contains(subject))) {
      final instructionEnd = line.indexOf(':');
      line = instructionEnd > 0
          ? line.substring(0, instructionEnd).trim()
          : 'Veckans glosor';
    }
    final id = schoolDraftId(letter, sourceText, familyId, uid);
    if (!seen.add(id)) continue;
    results.add(
      HomeworkItem(
        id: id,
        familyId: familyId,
        assignedToUserId: uid,
        title: line.length <= 85 ? line : '${line.substring(0, 82)}…',
        subject: subject.isEmpty ? 'Övrigt' : subject,
        topic: letter.title,
        extractedText: sourceText,
        source: letter.fromVardag ? 'vardag' : 'veckobrev',
        dueAt: explicitSchoolDate(sourceText, letter.publishedAt ?? now),
        ttsPreference: HomeworkTtsPreference.system,
        status: HomeworkStatus.todo,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  return results;
}
