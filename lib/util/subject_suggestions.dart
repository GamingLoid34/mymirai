import '../models/homework_item.dart';

/// Vanliga svenska skolämnen åk 1–9 (roadmap Chunk M).
const List<String> kStandardSchoolSubjects = [
  'Bild',
  'Biologi',
  'Engelska',
  'Franska',
  'Fysik',
  'Geografi',
  'Hemkunskap',
  'Historia',
  'Idrott',
  'Kemi',
  'Matematik',
  'Modersmål',
  'Musik',
  'NO',
  'Religion',
  'Samhällskunskap',
  'Slöjd',
  'SO',
  'Spanska',
  'Svenska',
  'Teknik',
  'Tyska',
];

/// Union av standardlistan + ämnen som redan finns i familjens läxor, sorterat.
List<String> mergedSubjectOptions(Iterable<HomeworkItem> homeworks) {
  final fromData = <String>{};
  for (final h in homeworks) {
    final t = h.subject.trim();
    if (t.isNotEmpty && t != 'Ämne') fromData.add(t);
  }
  final all = <String>{...kStandardSchoolSubjects, ...fromData};
  final out = all.toList();
  out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}
