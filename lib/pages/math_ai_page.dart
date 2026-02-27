import 'package:flutter/material.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';
import 'package:my_mirai/services/groq_service.dart';

/// AI-sida för matte: textbaserade lästal. Svårighetsgrad styrs av årskurs.
class MathAiPage extends StatefulWidget {
  final AppUser currentUser;
  final AppUser? selectedChild;
  final int schoolYear;

  const MathAiPage({
    super.key,
    required this.currentUser,
    this.selectedChild,
    required this.schoolYear,
  });

  @override
  State<MathAiPage> createState() => _MathAiPageState();
}

class _MathAiPageState extends State<MathAiPage> {
  final _answerController = TextEditingController();
  String? _problem;
  String? _correctAnswer;
  bool _loading = false;
  bool _answered = false;
  bool _correct = false;

  static const _groqApiKey = String.fromEnvironment('GROQ_API_KEY', defaultValue: ''); // Eller använd AppConfig

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_groqApiKey.isEmpty) {
      setState(() => _problem = 'Groq API-nyckel saknas. Kör med --dart-define=GROQ_API_KEY=xxx');
      return;
    }
    setState(() {
      _loading = true;
      _problem = null;
      _correctAnswer = null;
      _answered = false;
    });
    try {
      final groq = GroqService(apiKey: _groqApiKey);
      final prompt = 'Skapa ett enda matteproblem som lästal (textbaserat) för årskurs ${widget.schoolYear} i Sverige. '
          'Svårighetsgraden ska passa åldern. Svara i formatet:\nPROBLEM: [texten]\nSVAR: [det numeriska svaret]';
      final res = await groq.chat(
        'Du är en matematiklärare för barn. Skapa korta, tydliga problem.',
        prompt,
      );
      String? problem;
      String? answer;
      for (final line in res.split('\n')) {
        if (line.toUpperCase().startsWith('PROBLEM:')) {
          problem = line.replaceFirst(RegExp(r'^PROBLEM:\s*', caseSensitive: false), '').trim();
        } else if (line.toUpperCase().startsWith('SVAR:')) {
          answer = line.replaceFirst(RegExp(r'^SVAR:\s*', caseSensitive: false), '').trim();
        }
      }
      if (mounted) setState(() {
        _problem = problem ?? res;
        _correctAnswer = answer;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _problem = 'Fel: $e';
        _loading = false;
      });
    }
  }

  void _check() {
    final userAnswer = _answerController.text.trim();
    final correct = _correctAnswer != null &&
        userAnswer.replaceAll(' ', '').toLowerCase() ==
            _correctAnswer!.replaceAll(' ', '').toLowerCase();
    setState(() {
      _answered = true;
      _correct = correct;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI – Läs och räkna')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient(context)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (_problem != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppTheme.glassCard(context: context),
                  child: Text(_problem!, style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _answerController,
                  decoration: const InputDecoration(
                    labelText: 'Ditt svar',
                  ),
                ),
                const SizedBox(height: 16),
                if (!_answered)
                  FilledButton(onPressed: _check, child: const Text('Kolla svar'))
                else ...[
                  Icon(
                    _correct ? Icons.check_circle : Icons.cancel,
                    color: _correct ? Colors.green : Colors.red,
                    size: 48,
                  ),
                  Text(_correct ? 'Rätt!' : 'Fel. Rätt svar: $_correctAnswer'),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _generate, child: const Text('Nytt problem')),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
