import 'package:flutter_test/flutter_test.dart';

/// Testar klientens defensiva parsning av metadata-svaret från
/// suggestHomeworkMetadata (Cloud Function).
///
/// Parsningen är inbäddad i [AiService.suggestHomeworkMetadata] men
/// logiken är enkel nog att testa direkt via hjälpfunktioner nedan.

// ── hjälpfunktioner som speglar AiService-logiken ────────────────────────

String _trimmedString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  return v.toString().trim();
}

const _allowedTypes = ['text', 'vocabulary', 'math'];

Map<String, dynamic>? _payload(dynamic raw) {
  if (raw == null || raw is! Map) return null;
  try {
    return Map<String, dynamic>.from(raw);
  } catch (_) {
    return null;
  }
}

({
  String title,
  String subject,
  DateTime? dueAt,
  String homeworkType,
  double confidence,
}) _parseMetadataSvar(Map<String, dynamic>? data) {
  if (data == null) {
    return (
      title: 'Ny läxa',
      subject: 'Ämne',
      dueAt: null,
      homeworkType: 'text',
      confidence: 0.5,
    );
  }
  final title = _trimmedString(data['title']).isEmpty
      ? 'Ny läxa'
      : _trimmedString(data['title']);
  final subject = _trimmedString(data['subject']).isEmpty
      ? 'Ämne'
      : _trimmedString(data['subject']);

  final rawDue = data['dueAtIso'];
  DateTime? dueAt;
  if (rawDue is String && rawDue.trim().isNotEmpty) {
    try {
      dueAt = DateTime.parse(rawDue.trim());
    } catch (_) {
      dueAt = null;
    }
  }

  final rawType = _trimmedString(data['homeworkType']);
  final homeworkType = _allowedTypes.contains(rawType) ? rawType : 'text';

  final rawConf = data['confidence'];
  double confidence = 0.5;
  if (rawConf is num) {
    confidence = rawConf.toDouble().clamp(0.0, 1.0);
  }

  return (
    title: title,
    subject: subject,
    dueAt: dueAt,
    homeworkType: homeworkType,
    confidence: confidence,
  );
}

// ── tester ────────────────────────────────────────────────────────────────

void main() {
  group('Klientparsning av metadata-svar', () {
    test('giltigt svar tolkas korrekt', () {
      final svar = _parseMetadataSvar({
        'title': 'Glosor v.38 – engelska',
        'subject': 'Engelska',
        'dueAtIso': '2026-09-18',
        'homeworkType': 'vocabulary',
        'confidence': 0.9,
      });
      expect(svar.title, 'Glosor v.38 – engelska');
      expect(svar.subject, 'Engelska');
      expect(svar.dueAt, DateTime(2026, 9, 18));
      expect(svar.homeworkType, 'vocabulary');
      expect(svar.confidence, closeTo(0.9, 0.001));
    });

    test('saknade fält ger fallback-värden', () {
      final svar = _parseMetadataSvar({});
      expect(svar.title, 'Ny läxa');
      expect(svar.subject, 'Ämne');
      expect(svar.dueAt, isNull);
      expect(svar.homeworkType, 'text');
      expect(svar.confidence, closeTo(0.5, 0.001));
    });

    test('null-payload ger fallback', () {
      final svar = _parseMetadataSvar(null);
      expect(svar.title, 'Ny läxa');
      expect(svar.homeworkType, 'text');
    });

    test('ogiltigt datum ger null', () {
      final svar = _parseMetadataSvar({
        'title': 'Test',
        'subject': 'Matte',
        'dueAtIso': 'inte-ett-datum',
        'homeworkType': 'math',
        'confidence': 0.7,
      });
      expect(svar.dueAt, isNull);
    });

    test('okänd homeworkType ger text', () {
      final svar = _parseMetadataSvar({
        'title': 'Test',
        'subject': 'SO',
        'dueAtIso': null,
        'homeworkType': 'quiz',
        'confidence': 0.6,
      });
      expect(svar.homeworkType, 'text');
    });

    test('confidence klampas till 0–1', () {
      final over = _parseMetadataSvar({'confidence': 1.5});
      expect(over.confidence, closeTo(1.0, 0.001));

      final under = _parseMetadataSvar({'confidence': -0.3});
      expect(under.confidence, closeTo(0.0, 0.001));
    });

    test('tom titel ger Ny läxa', () {
      final svar = _parseMetadataSvar({'title': '   ', 'subject': 'Bild'});
      expect(svar.title, 'Ny läxa');
    });

    test('homeworkType math tolkas korrekt', () {
      final svar = _parseMetadataSvar({
        'title': 'Multiplikation',
        'subject': 'Matematik',
        'dueAtIso': null,
        'homeworkType': 'math',
        'confidence': 0.85,
      });
      expect(svar.homeworkType, 'math');
    });

    test('_payload returnerar null för icke-Map', () {
      expect(_payload(null), isNull);
      expect(_payload('sträng'), isNull);
      expect(_payload(42), isNull);
    });
  });
}
