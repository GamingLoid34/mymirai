import 'package:mime/mime.dart';

/// Gör filnamn till en rimlig rubrik (utan ändelse, mellanslag istället för _).
String suggestedTitleFromFileName(String fileName) {
  var base = fileName.trim();
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (base.isEmpty) return 'Ny uppgift';
  return base[0].toUpperCase() + base.substring(1);
}

/// Enkla nyckelord i filnamn → ämne (fritext kan ändras i formuläret).
String? guessSubjectFromFileName(String fileName) {
  final n = fileName.toLowerCase();
  if (n.contains('matte') ||
      n.contains('math') ||
      n.contains('algebra') ||
      n.contains('geometri')) {
    return 'Matematik';
  }
  if (n.contains('svenska') || n.contains('läsning')) return 'Svenska';
  if (n.contains('engelska') || n.contains('english')) return 'Engelska';
  if (n.contains('historia') ||
      n.contains('viking') ||
      n.contains('so ') ||
      n.startsWith('so')) {
    return 'Historia';
  }
  if (n.contains('fysik') ||
      n.contains('kemi') ||
      n.contains('biologi') ||
      n.contains('no ')) {
    return 'NO';
  }
  if (n.contains('musik')) return 'Musik';
  if (n.contains('slöjd')) return 'Slöjd';
  return null;
}

String? contentTypeForFileName(String fileName) {
  return lookupMimeType(fileName);
}
