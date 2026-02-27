import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';
import 'package:my_mirai/features/medcalc/medcalc_engine.dart';
import 'package:my_mirai/features/medcalc/medcalc_repository.dart';

class NursingProgramPage extends StatelessWidget {
  final AppUser currentUser;

  const NursingProgramPage({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sjuksköterskeprogrammet')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient(context)),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Moduler',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Välj en modul för träning med fokus på säkra beräkningar.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.mutedText(context),
                  ),
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MedcalcLandingPage(currentUser: currentUser),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: AppTheme.glassCard(context: context),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.calculate_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Läkemedelsberäkning (Säker)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Deterministisk motor med dubbelberäkning',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MedcalcLandingPage extends StatefulWidget {
  final AppUser currentUser;

  const MedcalcLandingPage({super.key, required this.currentUser});

  @override
  State<MedcalcLandingPage> createState() => _MedcalcLandingPageState();
}

class _MedcalcLandingPageState extends State<MedcalcLandingPage> {
  final _repository = MedcalcRepository();
  late Future<String> _formulaVersionFuture;

  @override
  void initState() {
    super.initState();
    _formulaVersionFuture = _repository.fetchActiveFormulaVersion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Läkemedelsberäkning (Säker)')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient(context)),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Utbildningsläge: slutsvar beräknas endast med regelstyrd motor (ingen AI) och dubbelverifiering A/B.',
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<String>(
              future: _formulaVersionFuture,
              builder: (context, snapshot) {
                final version = snapshot.data ?? MedcalcRepository.localFormulaVersion;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Aktiv formelversion: $version',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            _ModeCard(
              title: 'Träna',
              subtitle: 'Stegvis inmatning + facit och metodförklaring',
              icon: Icons.school_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MedcalcPracticePage(currentUser: widget.currentUser),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              title: 'Tentamode',
              subtitle: 'Poäng och tidtagning utan ledtrådar innan svar',
              icon: Icons.timer_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MedcalcExamPage(currentUser: widget.currentUser),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: AppTheme.glassCard(context: context),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedText(context),
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class MedcalcPracticePage extends StatefulWidget {
  final AppUser currentUser;

  const MedcalcPracticePage({super.key, required this.currentUser});

  @override
  State<MedcalcPracticePage> createState() => _MedcalcPracticePageState();
}

class _MedcalcPracticePageState extends State<MedcalcPracticePage> {
  final _engine = MedcalcEngine.instance;
  final _controllers = <String, TextEditingController>{};
  late MedcalcFormulaType _selectedFormula;
  MedcalcResult? _result;
  String? _error;
  bool _savingAttempt = false;

  @override
  void initState() {
    super.initState();
    _selectedFormula = MedcalcEngine.templates.first.formulaType;
    _syncControllers();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  MedcalcTemplate get _template => _engine.templateFor(_selectedFormula);

  void _syncControllers() {
    final neededKeys = _template.inputs.map((input) => input.key).toSet();
    final existingKeys = _controllers.keys.toList();

    for (final key in existingKeys) {
      if (!neededKeys.contains(key)) {
        _controllers[key]?.dispose();
        _controllers.remove(key);
      }
    }

    for (final input in _template.inputs) {
      _controllers.putIfAbsent(input.key, TextEditingController.new);
    }
  }

  Future<void> _calculate() async {
    final inputs = <String, String>{};
    for (final field in _template.inputs) {
      inputs[field.key] = _controllers[field.key]!.text.trim();
    }

    try {
      final result = _engine.calculate(_selectedFormula, inputs);
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = null;
      });
      await _logAttempt(
        mode: 'practice',
        result: result,
        rawInputs: inputs,
        isCorrect: null,
      );
    } on MedcalcValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _result = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunde inte beräkna: $e';
        _result = null;
      });
    }
  }

  Future<void> _logAttempt({
    required String mode,
    required MedcalcResult result,
    required Map<String, String> rawInputs,
    required bool? isCorrect,
  }) async {
    if (_savingAttempt) return;
    _savingAttempt = true;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUser.id)
          .collection('medcalc_attempts')
          .add({
        'mode': mode,
        'formulaType': _selectedFormula.shortCode,
        'formulaLabel': _selectedFormula.label,
        'rawInputs': rawInputs,
        'normalizedInputs': {
          for (final entry in result.normalizedInputs.entries)
            entry.key: entry.value.format(6),
        },
        'result': {
          'value': result.formattedResult,
          'unit': result.template.resultUnit,
          'displayDecimals': result.template.displayDecimals,
          'methodA': result.formattedMethodA,
          'methodB': result.formattedMethodB,
          'methodsMatch': result.methodsMatch,
          'isCorrect': isCorrect,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Loggning ska aldrig blockera träningsflödet.
    } finally {
      _savingAttempt = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Träna - Läkemedelsberäkning')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient(context)),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<MedcalcFormulaType>(
              value: _selectedFormula,
              items: MedcalcEngine.templates
                  .map(
                    (template) => DropdownMenuItem(
                      value: template.formulaType,
                      child: Text(template.title),
                    ),
                  )
                  .toList(),
              decoration: const InputDecoration(
                labelText: 'Beräkningstyp',
              ),
              onChanged: (next) {
                if (next == null) return;
                setState(() {
                  _selectedFormula = next;
                  _result = null;
                  _error = null;
                  _syncControllers();
                });
              },
            ),
            const SizedBox(height: 10),
            Text(
              _template.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.mutedText(context),
                  ),
            ),
            const SizedBox(height: 14),
            ..._template.inputs.map((input) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _controllers[input.key],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: input.label,
                    hintText: input.hint,
                    suffixText: input.unit,
                    helperText:
                        'Tillåtet intervall: ${input.min.format(2)} - ${input.max.format(2)} ${input.unit}',
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _calculate,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Beräkna säkert'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Colors.red[900],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.glassCard(context: context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resultat',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          '${_result!.formattedResult} ${_result!.template.resultUnit}',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'A/B verifierad',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Metod A: ${_result!.formattedMethodA} ${_result!.template.resultUnit}'),
                    Text('Metod B: ${_result!.formattedMethodB} ${_result!.template.resultUnit}'),
                    const SizedBox(height: 12),
                    const Text(
                      'Steg',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    ..._result!.steps.map(
                      (step) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Icon(Icons.check_circle_rounded, size: 16),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(step)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MedcalcExamPage extends StatefulWidget {
  final AppUser currentUser;

  const MedcalcExamPage({super.key, required this.currentUser});

  @override
  State<MedcalcExamPage> createState() => _MedcalcExamPageState();
}

class _MedcalcExamPageState extends State<MedcalcExamPage> {
  final _repository = MedcalcRepository();
  final _answerController = TextEditingController();
  final _stopwatch = Stopwatch();
  Timer? _ticker;

  late List<MedcalcExamQuestion> _questions;
  int _index = 0;
  int _score = 0;
  String? _feedback;
  bool? _lastCorrect;
  bool _submitted = false;
  bool _completed = false;
  bool _loadingQuestions = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _startNewSession();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _answerController.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  Future<void> _startNewSession() async {
    setState(() {
      _loadingQuestions = true;
      _loadError = null;
      _completed = false;
      _submitted = false;
      _feedback = null;
      _lastCorrect = null;
      _answerController.clear();
    });

    late List<MedcalcExamQuestion> loadedQuestions;
    try {
      loadedQuestions = await _repository.fetchExamQuestions(count: 8);
    } catch (e) {
      _loadError = 'Kunde inte hämta frågebank: $e';
      loadedQuestions = MedcalcExamFactory.generate(count: 8);
    }

    if (!mounted) return;
    _questions = loadedQuestions;
    _index = 0;
    _score = 0;

    _ticker?.cancel();
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() {
      _loadingQuestions = false;
    });
  }

  MedcalcExamQuestion get _currentQuestion => _questions[_index];

  String get _elapsedText {
    final elapsed = _stopwatch.elapsed;
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _submitAnswer() async {
    if (_submitted) return;
    final rawAnswer = _answerController.text.trim();
    if (rawAnswer.isEmpty) {
      setState(() => _feedback = 'Ange ett svar innan du skickar in.');
      return;
    }

    try {
      final userValue = ExactDecimal.parse(rawAnswer);
      final expected = _currentQuestion.expected.finalValue;
      final decimals = _currentQuestion.expected.template.displayDecimals;
      final isCorrect = userValue.equalsRounded(expected, decimals);

      if (isCorrect) _score += 1;

      setState(() {
        _submitted = true;
        _lastCorrect = isCorrect;
        _feedback = isCorrect
            ? 'Rätt! ${expected.format(decimals)} ${_currentQuestion.expected.template.resultUnit}'
            : 'Fel. Rätt svar är ${expected.format(decimals)} ${_currentQuestion.expected.template.resultUnit}.';
      });

      await _logExamAttempt(
        question: _currentQuestion,
        rawAnswer: rawAnswer,
        isCorrect: isCorrect,
      );
    } on MedcalcValidationException catch (e) {
      setState(() => _feedback = e.message);
    } catch (e) {
      setState(() => _feedback = 'Kunde inte tolka svaret: $e');
    }
  }

  Future<void> _nextQuestion() async {
    if (!_submitted) return;

    if (_index >= _questions.length - 1) {
      _stopwatch.stop();
      _ticker?.cancel();
      setState(() => _completed = true);
      await _logExamSession();
      return;
    }

    setState(() {
      _index += 1;
      _submitted = false;
      _feedback = null;
      _lastCorrect = null;
      _answerController.clear();
    });
  }

  Future<void> _logExamAttempt({
    required MedcalcExamQuestion question,
    required String rawAnswer,
    required bool isCorrect,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUser.id)
          .collection('medcalc_attempts')
          .add({
        'mode': 'exam',
        'formulaType': question.formulaType.shortCode,
        'questionId': question.id,
        'questionPrompt': question.prompt,
        'rawInputs': question.rawInputs,
        'rawAnswer': rawAnswer,
        'expected': question.expected.formattedResult,
        'expectedUnit': question.expected.template.resultUnit,
        'isCorrect': isCorrect,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Loggning får inte stoppa användaren.
    }
  }

  Future<void> _logExamSession() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUser.id)
          .collection('medcalc_sessions')
          .add({
        'mode': 'exam',
        'totalQuestions': _questions.length,
        'score': _score,
        'durationSeconds': _stopwatch.elapsed.inSeconds,
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Session-loggning är best-effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tentamode - Läkemedelsberäkning')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient(context)),
        child: _loadingQuestions
            ? _buildLoadingView(context)
            : (_completed ? _buildSummary(context) : _buildQuestionView(context)),
      ),
    );
  }

  Widget _buildLoadingView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              _loadError == null
                  ? 'Laddar tentafrågor...'
                  : 'Frågebank kunde inte laddas, använder lokal fallback.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionView(BuildContext context) {
    final question = _currentQuestion;
    final progress = (_index + 1) / _questions.length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_loadError != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_loadError!),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Text(
              'Fråga ${_index + 1}/${_questions.length}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _elapsedText,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.glassCard(context: context),
          child: Text(
            question.prompt,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _answerController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: !_submitted,
          decoration: InputDecoration(
            labelText: 'Ditt svar',
            hintText: 'Ange numeriskt värde',
            suffixText: question.expected.template.resultUnit,
          ),
        ),
        const SizedBox(height: 12),
        if (_feedback != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_lastCorrect ?? false)
                  ? Colors.green.withOpacity(0.14)
                  : Colors.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _feedback!,
              style: TextStyle(
                color: (_lastCorrect ?? false) ? Colors.green[900] : Colors.red[900],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 14),
        if (!_submitted)
          FilledButton(
            onPressed: _submitAnswer,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Skicka svar'),
          )
        else
          FilledButton(
            onPressed: _nextQuestion,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(_index >= _questions.length - 1 ? 'Visa resultat' : 'Nästa fråga'),
          ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final total = _questions.length;
    final percentage = total == 0 ? 0 : (_score * 100 / total).round();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: AppTheme.glassCard(context: context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tentamode klart',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text('Poäng: $_score / $total'),
              Text('Andel rätt: $percentage%'),
              Text('Tid: $_elapsedText'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _startNewSession,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Starta nytt tentapass'),
        ),
      ],
    );
  }
}
