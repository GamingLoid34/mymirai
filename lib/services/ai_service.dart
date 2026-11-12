import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/math_problem_entry.dart';
import '../models/test_question_item.dart';
import '../models/vocabulary_entry.dart';

/// Tjänsten kunde inte slutföra anropet (nät, server, timeout m.m.).
class AiUnavailableException implements Exception {
  AiUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'AiUnavailableException: $message';
}

/// Användaren är inte inloggad hos Firebase Auth.
class AiAuthException implements Exception {
  AiAuthException(this.message);
  final String message;
  @override
  String toString() => 'AiAuthException: $message';
}

/// Inmatningen uppfyller inte serverns krav (längd m.m.).
class AiInvalidInputException implements Exception {
  AiInvalidInputException(this.message);
  final String message;
  @override
  String toString() => 'AiInvalidInputException: $message';
}

/// Filformatet stöds inte (ännu) på servern.
class AiUnsupportedAttachmentException implements Exception {
  AiUnsupportedAttachmentException(this.message);
  final String message;
  @override
  String toString() => 'AiUnsupportedAttachmentException: $message';
}

/// Läxan saknar sammanfattning (Cloud Function `generateFlashcards`).
class AiNoSummaryException implements Exception {
  AiNoSummaryException(this.message);
  final String message;
  @override
  String toString() => 'AiNoSummaryException: $message';
}

class GenerateFlashcardsResult {
  const GenerateFlashcardsResult({
    required this.deckId,
    required this.cards,
  });

  final String deckId;
  final List<({String front, String back, String? sourceQuote})> cards;
}

/// Cachad ElevenLabs-uppläsning av ett dokument (`documentAudio`, VO-01).
class DocumentAudioResult {
  const DocumentAudioResult({required this.audioUrl, required this.truncated});
  final String audioUrl;
  final bool truncated;
}

/// Molnsaga + signerad ljud-URL (`listeningStory`, chunk W).
class PremiumListeningStoryResult {
  const PremiumListeningStoryResult({
    required this.storyText,
    required this.audioUrl,
    this.title,
  });

  final String storyText;
  final String audioUrl;
  final String? title;
}

class GradeResult {
  const GradeResult({
    required this.verdict,
    required this.feedback,
  });

  final String verdict;
  final String feedback;
}

/// AI-förslag på läxans metadata (titel, ämne, datum, typ).
class HomeworkMetadataSuggestion {
  const HomeworkMetadataSuggestion({
    required this.title,
    required this.subject,
    this.dueAt,
    required this.homeworkType,
    required this.confidence,
  });

  final String title;
  final String subject;
  final DateTime? dueAt;

  /// `text` | `vocabulary` | `math`
  final String homeworkType;

  /// 0.0–1.0
  final double confidence;
}

/// Barn- vs vuxensammanfattning för [summarizeHomework] (`audience`).
enum SummarizeAudience { child, adult }

/// Svar från [extractTextFromAttachment]: extraherad text ur bilaga.
class ExtractedText {
  const ExtractedText({
    required this.text,
    required this.source,
    this.warning,
  });

  /// Råtext (max 50 000 tecken server-side).
  final String text;

  /// Källa: `pdf` | `image` | `docx`
  final String source;

  /// t.ex. `no_text_layer` för skannad PDF.
  final String? warning;
}

/// Parsar Firebase Callable `data`; undvik `null`/felaktig struktur som ger cast-krasch.
Map<String, dynamic>? _callablePayload(dynamic raw) {
  if (raw == null || raw is! Map) return null;
  try {
    return Map<String, dynamic>.from(raw);
  } catch (_) {
    return null;
  }
}

String _callableTrimmedString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  return v.toString().trim();
}

/// Korta, läsliga fel (Firebase kan skicka HTML/strängmurar för INTERNAL).
String _httpsUserMessage(FirebaseFunctionsException e, String fallback) {
  final m = e.message?.trim() ?? '';
  if (m.isEmpty) return fallback;
  final one = m.split(RegExp(r'[\r\n]+')).first.trim();
  final bad =
      one.length > 280 ||
          one.contains('<html') ||
          one.contains('<!DOCTYPE');
  return bad ? fallback : one;
}

class ExtractedUrl {
  const ExtractedUrl({
    required this.text,
    required this.title,
    required this.sourceType,
    required this.sourceUrl,
  });

  /// Råtext (max 50 000 tecken server-side).
  final String text;

  final String title;

  /// `article`.
  final String sourceType;

  /// Den inklistrade webbadressen.
  final String sourceUrl;
}

/// Anropar Cloud Functions (region [europe-west1]).
class AiService {
  AiService({FirebaseFunctions? functions})
    : _injectedFunctions = functions;

  final FirebaseFunctions? _injectedFunctions;
  late final FirebaseFunctions _functions =
      _injectedFunctions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<String> summarize(
    String text, {
    String? gradeHint,
    SummarizeAudience audience = SummarizeAudience.child,
  }) async {
    final callable = _functions.httpsCallable('summarizeHomework');
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'text': text,
        if (gradeHint != null && gradeHint.trim().isNotEmpty) 'gradeHint': gradeHint.trim(),
        'audience': audience == SummarizeAudience.adult ? 'adult' : 'child',
      });
      final data = result.data;
      final summary = data['summary'] as String?;
      if (summary == null || summary.isEmpty) {
        throw AiUnavailableException(
          'Fick tomt svar från servern. Försök igen om en stund.',
        );
      }
      return summary;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            'Du måste vara inloggad för att använda AI-sammanfattning.',
          );
        case 'invalid-argument':
          throw AiInvalidInputException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Längd ska vara 20–50 000 tecken.',
          );
        default:
          throw AiUnavailableException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Något gick fel vid AI-anrop. Försök igen senare.',
          );
      }
    } catch (e) {
      if (e is AiAuthException || e is AiInvalidInputException || e is AiUnavailableException) rethrow;
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Läser text från uppladdad bilaga (PDF med text, DOCX, foto med OCR).
  Future<ExtractedText> extractFromAttachment(
    String homeworkId, {
    int? attachmentIndex,
  }) async {
    final callable = _functions.httpsCallable('extractTextFromAttachment');
    try {
      debugPrint('[AiService] extract: homeworkId="$homeworkId" length=${homeworkId.length}');
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'homeworkId': homeworkId,
        if (attachmentIndex != null && attachmentIndex >= 0)
          'attachmentIndex': attachmentIndex,
      });
      final data = result.data;
      final text = data['text'] as String? ?? '';
      final source = data['source'] as String? ?? '';
      final warning = data['warning'] as String?;
      if (source != 'pdf' && source != 'image' && source != 'docx') {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      return ExtractedText(text: text, source: source, warning: warning);
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Du har inte behörighet att läsa den här bilagan.',
          );
        case 'invalid-argument':
        case 'failed-precondition':
          throw AiInvalidInputException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Bilagan kunde inte användas. Spara om och försök igen.',
          );
        case 'unimplemented':
          throw AiUnsupportedAttachmentException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Det här filformatet stöds inte ännu.',
          );
        case 'resource-exhausted':
          throw AiInvalidInputException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Filen är för stor (max 25 MB).',
          );
        case 'not-found':
          throw AiInvalidInputException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Läxan hittades inte.',
          );
        default:
          throw AiUnavailableException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Kunde inte läsa bilagan. Försök igen senare.',
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException ||
          e is AiUnsupportedAttachmentException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Läser text från vuxen-dokumentets bilaga (PDF, DOCX, bild med OCR).
  Future<ExtractedText> extractFromDocument(String documentId) async {
    final callable = _functions.httpsCallable('extractTextFromDocument');
    try {
      debugPrint(
        '[AiService] extractDoc: documentId="$documentId" length=${documentId.length}',
      );
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'documentId': documentId,
      });
      final data = result.data;
      final text = data['text'] as String? ?? '';
      final source = data['source'] as String? ?? '';
      final warning = data['warning'] as String?;
      if (source != 'pdf' && source != 'image' && source != 'docx') {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      return ExtractedText(text: text, source: source, warning: warning);
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Du har inte behörighet att läsa den här bilagan.',
          );
        case 'invalid-argument':
        case 'failed-precondition':
          throw AiInvalidInputException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Bilagan kunde inte användas. Spara om och försök igen.',
          );
        case 'unimplemented':
          throw AiUnsupportedAttachmentException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Det här filformatet stöds inte ännu.',
          );
        case 'resource-exhausted':
          throw AiInvalidInputException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Filen är för stor (max 25 MB).',
          );
        case 'not-found':
          final hm = e.message ?? '';
          final low = hm.toLowerCase();
          // Server‑HttpsError är svensk; Firebase‑klienten kan sända NOT_FOUND/tom sträng.
          if (hm.contains('hittades') || low.contains('dokumentet')) {
            throw AiInvalidInputException(
              hm.isNotEmpty ? hm : 'Dokumentet hittades inte i molnet.',
            );
          }
          throw AiUnavailableException(
            hm.isNotEmpty
                ? '$hm — Deployment? Kör firebase deploy '
                    '--only functions:extractTextFromDocument '
                    '--project=la-familia-5d9f5 (region europe-west1).'
                : 'extractTextFromDocument svarade not-found (callable saknas ofta '
                    'tills den deployats). firebase deploy '
                    '--only functions:extractTextFromDocument '
                    '--project=la-familia-5d9f5',
          );
        default:
          throw AiUnavailableException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Kunde inte läsa bilagan. Försök igen senare.',
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException ||
          e is AiUnsupportedAttachmentException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Hämtar artikeltext från en http(s)-länk (Cloud Function `extractFromUrl`).
  Future<ExtractedUrl> extractFromUrl(String url) async {
    final u = url.trim();
    if (u.length < 8) {
      throw AiInvalidInputException('Ogiltig adress.');
    }
    final callable = _functions.httpsCallable('extractFromUrl');
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'url': u,
      });
      final data = _callablePayload(result.data);
      if (data == null) {
        throw AiUnavailableException(
          'Ogiltigt svar från servern. Försök igen senare.',
        );
      }
      final text = _callableTrimmedString(data['text']);
      final title = _callableTrimmedString(data['title']);
      final sourceType = _callableTrimmedString(data['sourceType']);
      if (sourceType != 'article' || text.isEmpty) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      return ExtractedUrl(
        text: text,
        title: title,
        sourceType: sourceType,
        sourceUrl: u,
      );
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            _httpsUserMessage(
              e,
              'Du måste vara inloggad för att hämta länkar.',
            ),
          );
        case 'invalid-argument':
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Kunde inte läsa sidan.'),
          );
        case 'deadline-exceeded':
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Svaret tog för lång tid. Försök igen.'),
          );
        case 'not-found':
          final hm = e.message ?? '';
          final nf = hm.toUpperCase().replaceAll(RegExp(r'\s'), '');
          final callableMissing = hm.isEmpty || nf.contains('NOT_FOUND');
          if (callableMissing) {
            throw AiUnavailableException(
              'Molntjänsten extractFromUrl är inte installerad eller svarade not-found. '
              'Kör firebase deploy --only functions:extractFromUrl --project=la-familia-5d9f5.',
            );
          }
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte nå servern.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte hämta sidan. Prova annan källa eller försök senare.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  Future<GenerateFlashcardsResult> generateFlashcards(
    String homeworkId, {
    int count = 10,
  }) async {
    final callable = _functions.httpsCallable('generateFlashcards');
    try {
      final result =
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'homeworkId': homeworkId,
        'count': count,
      });
      final data = result.data;
      final deckId = data['deckId'] as String?;
      final rawCards = data['cards'];
      if (deckId == null || deckId.isEmpty) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      if (rawCards is! List<dynamic>) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      final cards = <({String front, String back, String? sourceQuote})>[];
      for (final e in rawCards) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final front = (m['front'] as String?)?.trim() ?? '';
          final back = (m['back'] as String?)?.trim() ?? '';
          final sqRaw = m['sourceQuote'];
          final sourceQuote =
              sqRaw is String && sqRaw.trim().isNotEmpty ? sqRaw.trim() : null;
          if (front.isNotEmpty && back.isNotEmpty) {
            cards.add(
              (front: front, back: back, sourceQuote: sourceQuote),
            );
          }
        }
      }
      if (cards.isEmpty) {
        throw AiUnavailableException('Fick inga flashcards tillbaka.');
      }
      return GenerateFlashcardsResult(deckId: deckId, cards: cards);
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Du har inte behörighet för den här åtgärden.',
          );
        case 'failed-precondition':
          final fp = e.message ?? '';
          if (fp.contains('familj')) {
            throw AiInvalidInputException(
              fp.isNotEmpty ? fp : 'Kontrollera familjen i La Familia.',
            );
          }
          throw AiNoSummaryException(
            'Generera först en sammanfattning av läxan.',
          );
        case 'invalid-argument':
        case 'not-found':
          throw AiInvalidInputException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Ogiltigt anrop.',
          );
        case 'internal':
        case 'unavailable':
        default:
          throw AiUnavailableException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Kunde inte skapa flashcards just nu.',
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException ||
          e is AiNoSummaryException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Roadmap v5: skapar flashcards med frågor/svar ur extraherad text (`parseQuestionsAndAnswers`).
  Future<String> parseQuestionsAndAnswers({required String homeworkId}) async {
    final id = homeworkId.trim();
    if (id.isEmpty) {
      throw AiInvalidInputException('homeworkId saknas.');
    }
    final callable = _functions.httpsCallable('parseQuestionsAndAnswers');
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'homeworkId': id,
      });
      final deckId = (result.data['deckId'] as String?)?.trim() ?? '';
      if (deckId.isEmpty) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      return deckId;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Du har inte behörighet för den här åtgärden.',
          );
        case 'invalid-argument':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Ogiltigt anrop.'),
          );
        case 'not-found':
          final hm = e.message ?? '';
          final nf = hm.toUpperCase().replaceAll(RegExp(r'\s'), '');
          final callableMissing = hm.isEmpty || nf.contains('NOT_FOUND');
          if (callableMissing) {
            throw AiUnavailableException(
              'Molntjänsten parseQuestionsAndAnswers saknas eller är inte deployad. '
              'Kör firebase deploy --only functions:parseQuestionsAndAnswers '
              '--project=la-familia-5d9f5 (region europe-west1).',
            );
          }
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Läxan hittades inte.'),
          );
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Kunde inte läsa materialet.'),
          );
        case 'internal':
        case 'unavailable':
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte tolka materialet just nu.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Chunk W: pedagogisk saga + ElevenLabs-ljud (`listeningStory`).
  Future<PremiumListeningStoryResult> listeningStory({
    String? homeworkId,
    String? text,
  }) async {
    final hw = homeworkId?.trim() ?? '';
    final tx = text?.trim() ?? '';
    if (hw.isEmpty && tx.isEmpty) {
      throw AiInvalidInputException('Ange homeworkId eller text.');
    }

    final callable = _functions.httpsCallable('listeningStory');
    try {
      final result =
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
        if (hw.isNotEmpty) 'homeworkId': hw,
        if (tx.isNotEmpty) 'text': tx,
      });
      final data = result.data;
      final story = (data['storyText'] as String?)?.trim() ?? '';
      final url = (data['audioUrl'] as String?)?.trim() ?? '';
      final title = (data['title'] as String?)?.trim();
      if (story.isEmpty || url.isEmpty) {
        throw AiUnavailableException('Ogiltigt svar från molnsagan.');
      }
      return PremiumListeningStoryResult(
        storyText: story,
        audioUrl: url,
        title: title,
      );
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Du har inte behörighet för den här åtgärden.',
          );
        case 'not-found':
          final hm = e.message ?? '';
          final nf = hm.toUpperCase().replaceAll(RegExp(r'\s'), '');
          final callableMissing = hm.isEmpty || nf.contains('NOT_FOUND');
          if (callableMissing) {
            throw AiUnavailableException(
              'Molntjänsten listeningStory saknas eller är inte deployad. '
              'Kör firebase deploy --only functions:listeningStory --project=la-familia-5d9f5 '
              '(region europe-west1). Sätt secrets: ELEVENLABS_API_KEY och ANTHROPIC_API_KEY.',
            );
          }
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Läxan eller texten hittades inte.'),
          );
        case 'invalid-argument':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Ogiltigt anrop.'),
          );
        case 'failed-precondition':
        case 'internal':
        case 'unavailable':
        default:
          throw AiUnavailableException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Molnsagan kunde inte skapas just nu.',
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// VO-01: cachad ElevenLabs-uppläsning av ett dokument (`documentAudio`).
  Future<DocumentAudioResult> documentAudio({required String documentId}) async {
    final id = documentId.trim();
    if (id.isEmpty) {
      throw AiInvalidInputException('Ange ett dokument-ID.');
    }

    final callable = _functions.httpsCallable('documentAudio');
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'documentId': id,
      });
      final data = result.data;
      final url = (data['audioUrl'] as String?)?.trim() ?? '';
      final truncated = data['truncated'] as bool? ?? false;
      if (url.isEmpty) {
        throw AiUnavailableException('Ogiltigt svar från ljudtjänsten.');
      }
      return DocumentAudioResult(audioUrl: url, truncated: truncated);
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Du har inte behörighet för den här åtgärden.',
          );
        case 'not-found':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Dokumentet hittades inte.'),
          );
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Dokumentet saknar text att läsa upp.'),
          );
        case 'invalid-argument':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Ogiltigt anrop.'),
          );
        case 'internal':
        case 'unavailable':
        default:
          throw AiUnavailableException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Kunde inte skapa uppläsning just nu.',
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  Future<GradeResult> gradeAnswer({
    required String deckId,
    required String cardId,
    required String userAnswer,
  }) async {
    final callable = _functions.httpsCallable('gradeAnswer');
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'deckId': deckId,
        'cardId': cardId,
        'userAnswer': userAnswer,
      });
      final data = result.data;
      final verdict = (data['verdict'] as String?)?.trim() ?? '';
      final feedback = (data['feedback'] as String?)?.trim() ?? '';
      if (feedback.isEmpty ||
          (verdict != 'correct' && verdict != 'partial' && verdict != 'wrong')) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      return GradeResult(verdict: verdict, feedback: feedback);
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Du har inte behörighet för den här åtgärden.',
          );
        case 'invalid-argument':
        case 'not-found':
        case 'failed-precondition':
          throw AiInvalidInputException(
            e.message?.isNotEmpty == true ? e.message! : 'Ogiltigt anrop.',
          );
        case 'internal':
        case 'unavailable':
        default:
          throw AiUnavailableException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Kunde inte bedöma svaret just nu.',
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Barnläge: slumpa prov från valda lekar (`generateTest`, Cloud Functions).
  Future<List<TestQuestionItem>> generateTest({
    required List<String> deckIds,
    int count = 15,
    bool mixWithMultipleChoice = true,
  }) async {
    final ids = [...deckIds.where((id) => id.trim().isNotEmpty)];
    final callable = _functions.httpsCallable('generateTest');
    try {
      final result =
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'deckIds': ids,
        'count': count,
        'mixWithMultipleChoice': mixWithMultipleChoice,
      });
      final raw = result.data['questions'];
      if (raw is! List<dynamic>) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      final out = <TestQuestionItem>[];
      for (final e in raw) {
        if (e is! Map) {
          throw AiUnavailableException('Ogiltigt svar från servern.');
        }
        out.add(TestQuestionItem.fromCloudMap(Map<String, dynamic>.from(e)));
      }
      if (out.isEmpty) {
        throw AiInvalidInputException('Inga frågor kunde skapas.');
      }
      return out;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Du har inte behörighet för den här åtgärden.',
          );
        case 'failed-precondition':
        case 'invalid-argument':
          throw AiInvalidInputException(
            e.message?.isNotEmpty == true ? e.message! : 'Ogiltigt anrop.',
          );
        case 'not-found':
          final nf = e.message?.trim() ?? '';
          final upperFlat = nf.toUpperCase().replaceAll(RegExp(r'\s'), '');
          // Saknad callable ger ofta tomt eller "NOT FOUND"; servern sänder t.ex. "Leken hittades inte."
          final callableMissing =
              nf.isEmpty || upperFlat.contains('NOT_FOUND');
          final serverDeckOrCard = nf.contains('Lek') || nf.contains('hitt');
          if (callableMissing && !serverDeckOrCard) {
            throw AiUnavailableException(
              'Molntjänsten generateTest saknas eller är inte igång än. '
              'Kör firebase deploy --only functions:generateTest '
              '--project=la-familia-5d9f5 (region europe-west1), vänta en stund och prova igen.',
            );
          }
          throw AiInvalidInputException(
            nf.isNotEmpty ? nf : 'Resursen hittades inte.',
          );
        case 'internal':
        case 'unavailable':
        default:
          throw AiUnavailableException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Kunde inte skapa provet just nu.',
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      if (e is FormatException) {
        final msg = e.message.trim();
        throw AiInvalidInputException(
          msg.isNotEmpty ? msg : 'Ogiltigt svar från servern.',
        );
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Strukturerar inklistrad glostext till par (Cloud Function `parseVocabulary`).
  Future<List<VocabularyEntry>> parseVocabulary({
    required String rawText,
    String sourceLanguage = 'English',
    String targetLanguage = 'Svenska',
  }) async {
    final callable = _functions.httpsCallable('parseVocabulary');
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'rawText': rawText,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
      });
      final rawItems = result.data['items'];
      if (rawItems is! List<dynamic>) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      final out = <VocabularyEntry>[];
      for (final e in rawItems) {
        if (e is Map) {
          final v = VocabularyEntry.fromMap(Map<String, dynamic>.from(e));
          if (v.isValid) out.add(v);
        }
      }
      if (out.isEmpty) {
        throw AiInvalidInputException('Inga giltiga glos-par i svaret.');
      }
      return out;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true
                ? e.message!
                : 'Du måste vara inloggad.',
          );
        case 'invalid-argument':
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Kunde inte tolka gloslistan.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte parsa glosor just nu.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Skapar flashcards från sparad glosläxa (`generateVocabularyFlashcards`).
  Future<({String deckId, int cardCount})> generateVocabularyFlashcards(
    String homeworkId,
  ) async {
    final callable = _functions.httpsCallable('generateVocabularyFlashcards');
    try {
      final result =
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'homeworkId': homeworkId,
      });
      final data = result.data;
      final deckId = data['deckId'] as String? ?? '';
      final n = data['cardCount'];
      final cardCount = n is int ? n : (n is num ? n.toInt() : 0);
      if (deckId.isEmpty) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      return (deckId: deckId, cardCount: cardCount);
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true ? e.message! : 'Saknar behörighet.',
          );
        case 'not-found':
        case 'invalid-argument':
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Kontrollera att glosorna är sparade.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte skapa gloskort just nu.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  Future<List<MathProblemEntry>> parseMathProblems(String extractedText) async {
    final callable = _functions.httpsCallable('parseMathProblems');
    try {
      final result =
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'extractedText': extractedText,
      });
      final raw = result.data['problems'];
      if (raw is! List<dynamic>) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      final out = <MathProblemEntry>[];
      for (final e in raw) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final t = (m['originalText'] as String?)?.trim() ?? '';
          if (t.isNotEmpty) out.add(MathProblemEntry(originalText: t));
        }
      }
      if (out.isEmpty) {
        throw AiInvalidInputException('Inga uppgifter hittades.');
      }
      return out;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
          throw AiAuthException(
            e.message?.isNotEmpty == true ? e.message! : 'Inloggning krävs.',
          );
        case 'invalid-argument':
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Texten gick inte att dela i uppgifter.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte analysera matteenheterna.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  Future<String> explainMathStep(String problemText) async {
    final callable = _functions.httpsCallable('explainMathStep');
    try {
      final result =
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'problemText': problemText,
      });
      final explanation = result.data['explanation'] as String? ?? '';
      if (explanation.trim().isEmpty) {
        throw AiUnavailableException('Tom förklaring från servern.');
      }
      return explanation.trim();
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
          throw AiAuthException(
            e.message?.isNotEmpty == true ? e.message! : 'Inloggning krävs.',
          );
        case 'invalid-argument':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Ogiltig uppgiftstext.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte förklara just nu.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  Future<List<String>> varyMathProblem(
    String problemText, {
    String? homeworkId,
    Object? gradeHint,
  }) async {
    final payload = <String, dynamic>{
      'problemText': problemText,
      if (homeworkId != null && homeworkId.trim().isNotEmpty)
        'homeworkId': homeworkId.trim(),
    };
    final gh = gradeHint;
    if (gh != null) {
      payload['gradeHint'] = gh;
    }
    final callable = _functions.httpsCallable('varyMathProblem');
    try {
      final result =
          await callable.call<Map<String, dynamic>>(payload);
      final raw = result.data['variants'];
      if (raw is! List<dynamic>) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      final out = raw
          .map((e) => e is String ? e.trim() : '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (out.length < 3) {
        throw AiUnavailableException('För få varianter i svaret.');
      }
      return out;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            e.message?.isNotEmpty == true ? e.message! : 'Saknar behörighet.',
          );
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(
              e,
              'Kan inte variera siffror för den här nivån.',
            ),
          );
        case 'invalid-argument':
        case 'not-found':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Ogiltigt anrop.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte skapa varianter.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Dokumentchatt; servern sparar turordning i `chat_turns`.
  Future<String> chatWithDocument({
    required String documentId,
    required String userMessage,
    List<Map<String, String>> history = const [],
  }) async {
    final callable = _functions.httpsCallable('chatWithDocument');
    try {
      final result =
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'documentId': documentId,
        'userMessage': userMessage,
        'history': history,
      });
      final reply = result.data['reply'] as String? ?? '';
      if (reply.trim().isEmpty) {
        throw AiUnavailableException('Tomt svar från servern.');
      }
      return reply.trim();
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            _httpsUserMessage(e, 'Saknar behörighet till dokumentet.'),
          );
        case 'not-found':
          final hm = e.message ?? '';
          final nf = hm.toUpperCase().replaceAll(RegExp(r'\s'), '');
          final callableMissing = hm.isEmpty || nf.contains('NOT_FOUND');
          if (callableMissing) {
            throw AiUnavailableException(
              'Molntjänsten chatWithDocument saknas eller svarade not-found. '
              'Kör firebase deploy --only functions:chatWithDocument --project=la-familia-5d9f5.',
            );
          }
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Dokumentet hittades inte.'),
          );
        case 'invalid-argument':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Kunde inte skicka meddelandet.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Chatt misslyckades. Försök igen.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// Föreslår titel, ämne, inlämningsdatum och typ baserat på extraherad text.
  Future<HomeworkMetadataSuggestion> suggestHomeworkMetadata({
    required String text,
    List<String>? knownSubjects,
  }) async {
    final callable = _functions.httpsCallable('suggestHomeworkMetadata');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'text': text,
        'clientToday': today,
        if (knownSubjects != null && knownSubjects.isNotEmpty)
          'knownSubjects': knownSubjects,
      });
      final data = _callablePayload(result.data);
      if (data == null) {
        throw AiUnavailableException('Ogiltigt svar från servern.');
      }
      final title = _callableTrimmedString(data['title']);
      final subject = _callableTrimmedString(data['subject']);
      final rawDue = data['dueAtIso'];
      DateTime? dueAt;
      if (rawDue is String && rawDue.trim().isNotEmpty) {
        try {
          dueAt = DateTime.parse(rawDue.trim());
        } catch (_) {
          dueAt = null;
        }
      }
      final rawType = _callableTrimmedString(data['homeworkType']);
      final homeworkType = ['text', 'vocabulary', 'math'].contains(rawType) ? rawType : 'text';
      final rawConf = data['confidence'];
      double confidence = 0.5;
      if (rawConf is num) {
        confidence = rawConf.toDouble().clamp(0.0, 1.0);
      }
      return HomeworkMetadataSuggestion(
        title: title.isEmpty ? 'Ny läxa' : title,
        subject: subject.isEmpty ? 'Ämne' : subject,
        dueAt: dueAt,
        homeworkType: homeworkType,
        confidence: confidence,
      );
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            _httpsUserMessage(e, 'Du måste vara inloggad för att använda AI-förslag.'),
          );
        case 'invalid-argument':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Texten är för kort eller för lång.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte tolka läxan just nu. Försök igen senare.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException || e is AiInvalidInputException || e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  Future<String> transcribeUserAudio({
    required String storagePath,
    String mimeType = 'audio/mpeg',
  }) async {
    final callable = _functions.httpsCallable('transcribeUserAudio');
    try {
      final result =
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'storagePath': storagePath,
        'mimeType': mimeType,
      });
      final text = result.data['text'] as String? ?? '';
      if (text.trim().isEmpty) {
        throw AiUnavailableException('Tom transkription.');
      }
      return text.trim();
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            _httpsUserMessage(e, 'Ogiltig lagringsväg eller inloggning.'),
          );
        case 'not-found':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Ljudfilen hittades inte.'),
          );
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Ingen tydlig text i ljudet.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Transkription misslyckades.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// VO-06: transkriberar en mötesinspelning (longRunningRecognize, GCS-URI).
  Future<int> transcribeRecording({
    required String documentId,
    String languageCode = 'sv-SE',
  }) async {
    final callable = _functions.httpsCallable('transcribeRecording');
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'documentId': documentId,
        'languageCode': languageCode,
      });
      final chars = (result.data['chars'] as num?)?.toInt() ?? 0;
      return chars;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            _httpsUserMessage(e, 'Du har inte behörighet för den här åtgärden.'),
          );
        case 'not-found':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Dokumentet hittades inte.'),
          );
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Dokumentet saknar ljudbilaga.'),
          );
        case 'invalid-argument':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Max 60 minuter i denna version.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Transkriptionen misslyckades. Försök igen senare.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// VO-07: städar talspråk (utfyllnadsord, grammatik) utan att ändra innehåll.
  Future<String> polishDictation({required String text}) async {
    final callable = _functions.httpsCallable('polishDictation');
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'text': text,
      });
      final polished = (result.data['polishedText'] as String?)?.trim() ?? '';
      if (polished.isEmpty) {
        throw AiUnavailableException('Tomt svar från städningen.');
      }
      return polished;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
          throw AiAuthException(_httpsUserMessage(e, 'Logga in igen.'));
        case 'invalid-argument':
          throw AiInvalidInputException(_httpsUserMessage(e, 'Ogiltig text.'));
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte städa texten just nu.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }

  /// VO-06: bygger en jobbsammanfattning (Beslut/Att göra/Öppna frågor) från transkriptet.
  Future<String> summarizeRecording({required String documentId}) async {
    final callable = _functions.httpsCallable('summarizeRecording');
    try {
      final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'documentId': documentId,
      });
      final summary = (result.data['summary'] as String?)?.trim() ?? '';
      if (summary.isEmpty) {
        throw AiUnavailableException('Tom sammanfattning.');
      }
      return summary;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          throw AiAuthException(
            _httpsUserMessage(e, 'Du har inte behörighet för den här åtgärden.'),
          );
        case 'not-found':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Dokumentet hittades inte.'),
          );
        case 'failed-precondition':
          throw AiInvalidInputException(
            _httpsUserMessage(e, 'Dokumentet saknar transkript att sammanfatta.'),
          );
        default:
          throw AiUnavailableException(
            _httpsUserMessage(e, 'Kunde inte skapa sammanfattning just nu.'),
          );
      }
    } catch (e) {
      if (e is AiAuthException ||
          e is AiInvalidInputException ||
          e is AiUnavailableException) {
        rethrow;
      }
      throw AiUnavailableException(
        'Kunde inte nå servern. Kontrollera nätet och försök igen.',
      );
    }
  }
}
