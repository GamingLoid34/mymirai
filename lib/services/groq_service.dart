import 'dart:convert';
import 'package:http/http.dart' as http;

/// Groq API (LLaMA-4) för AI-anrop.
class GroqService {
  static const _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'meta-llama/llama-4-scout-17b-16e-instruct';

  final String apiKey;

  GroqService({required this.apiKey});

  /// Skicka en chat-förfrågan till Groq.
  Future<String> chat(String systemPrompt, String userMessage) async {
    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'temperature': 0.5,
        'max_tokens': 2048,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Groq API error: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Inget svar från Groq');
    }
    final content = choices[0]['message']?['content']?.toString() ?? '';
    return content.trim();
  }

  /// AI-sammanfatta text.
  Future<String> summarize(String text, {String languageCode = 'sv'}) async {
    return chat(
      'Du är en pedagogisk assistent. Sammanfatta följande text kort och tydligt på svenska. Använd enkla meningar.',
      text,
    );
  }

  /// Skapa checklista (substeps) från text.
  Future<List<String>> createSubsteps(String text) async {
    final res = await chat(
      'Du är en pedagogisk assistent. Dela upp följande text i en numrerad checklista med konkreta steg. Svara ENDAST med listan, en steg per rad, format: 1. Steg ett 2. Steg två osv.',
      text,
    );
    final lines = res.split(RegExp(r'\d+\.\s*')).where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList();
    return lines;
  }

  /// Generera instuderingsfrågor.
  Future<List<Map<String, String>>> createStudyQuestions(String text) async {
    final res = await chat(
      'Du är en pedagogisk assistent. Skapa 3-5 instuderingsfrågor med svar baserat på texten. Svara i formatet: Q: fråga A: svar, varje par på en ny rad.',
      text,
    );
    final pairs = <Map<String, String>>[];
    final parts = res.split(RegExp(r'\n'));
    String? currentQ;
    for (final p in parts) {
      if (p.trim().toUpperCase().startsWith('Q:')) {
        currentQ = p.replaceFirst(RegExp(r'^Q:\s*', caseSensitive: false), '').trim();
      } else if (p.trim().toUpperCase().startsWith('A:')) {
        final a = p.replaceFirst(RegExp(r'^A:\s*', caseSensitive: false), '').trim();
        if (currentQ != null) {
          pairs.add({'front': currentQ, 'back': a});
          currentQ = null;
        }
      }
    }
    return pairs;
  }

  /// Skapa glosor för språk (från text).
  Future<List<Map<String, String>>> createFlashcards(String text, {String languageCode = 'sv'}) async {
    final res = await chat(
      'Du är en pedagogisk assistent. Skapa glosor (ord/fraser med översättning) från texten. Svara i formatet: ord = översättning, varje glosa på en ny rad. Minst 5 glosor.',
      text,
    );
    final cards = <Map<String, String>>[];
    for (final line in res.split('\n')) {
      final idx = line.indexOf('=');
      if (idx > 0) {
        cards.add({
          'front': line.substring(0, idx).trim(),
          'back': line.substring(idx + 1).trim(),
        });
      }
    }
    return cards;
  }
}
