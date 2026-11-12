import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_mirai/util/document_labels.dart';

void main() {
  test('file maps to Fil', () {
    final v = documentTypeVisual('file');
    expect(v.label, 'Fil');
    expect(v.icon, Icons.description_outlined);
  });

  test('article maps to Artikel', () {
    final v = documentTypeVisual('article');
    expect(v.label, 'Artikel');
    expect(v.icon, Icons.link_rounded);
  });

  test('text maps to Text', () {
    final v = documentTypeVisual('text');
    expect(v.label, 'Text');
    expect(v.icon, Icons.edit_outlined);
  });

  test('note maps to Anteckning', () {
    final v = documentTypeVisual('note');
    expect(v.label, 'Anteckning');
    expect(v.icon, Icons.sticky_note_2_outlined);
  });

  test('recording maps to Inspelning', () {
    final v = documentTypeVisual('recording');
    expect(v.label, 'Inspelning');
    expect(v.icon, Icons.mic_none_rounded);
  });

  test('unknown source type falls back to Dokument', () {
    final v = documentTypeVisual('something_else');
    expect(v.label, 'Dokument');
  });

  test('is case-insensitive and trims whitespace', () {
    expect(documentTypeVisual('  NOTE  ').label, 'Anteckning');
  });
}
