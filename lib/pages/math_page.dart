import 'dart:math';
import 'package:flutter/material.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';
import 'package:my_mirai/pages/math_ai_page.dart';

/// Matte-gym: slumpmässiga tal, dropdown för årskurs.
class MathPage extends StatefulWidget {
  final AppUser currentUser;
  final AppUser? selectedChild;

  const MathPage({super.key, required this.currentUser, this.selectedChild});

  @override
  State<MathPage> createState() => _MathPageState();
}

class _MathPageState extends State<MathPage> {
  int _schoolYear = 5;
  int _a = 0, _b = 0;
  final _answerController = TextEditingController();
  bool _checked = false;
  bool _correct = false;

  int get _answer => _a + _b;

  @override
  void initState() {
    super.initState();
    _newProblem();
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _newProblem() {
    final r = Random();
    final max = _schoolYear <= 2 ? 10 : _schoolYear <= 5 ? 100 : 1000;
    setState(() {
      _a = r.nextInt(max) + 1;
      _b = r.nextInt(max) + 1;
      _answerController.clear();
      _checked = false;
    });
  }

  void _check() {
    final userAnswer = int.tryParse(_answerController.text);
    setState(() {
      _checked = true;
      _correct = userAnswer == _answer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.selectedChild ?? widget.currentUser;
    final year = profile.schoolYear ?? _schoolYear;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matte-gym'),
        actions: [
          DropdownButton<int>(
            value: _schoolYear,
            underline: const SizedBox(),
            items: List.generate(9, (i) => i + 1)
                .map((y) => DropdownMenuItem(value: y, child: Text('Årskurs $y')))
                .toList(),
            onChanged: (v) => setState(() {
              _schoolYear = v ?? 5;
              _newProblem();
            }),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient(context)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Svårighetsgrad: årskurs $_schoolYear',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mutedText(context),
                    ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(32),
                decoration: AppTheme.glassCard(context: context),
                child: Column(
                  children: [
                    Text(
                      '$_a + $_b = ?',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _answerController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        hintText: 'Svara här',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_checked)
                      FilledButton(
                        onPressed: _check,
                        child: const Text('Kolla'),
                      )
                    else ...[
                      Icon(
                        _correct ? Icons.check_circle : Icons.cancel,
                        color: _correct ? Colors.green : Colors.red,
                        size: 48,
                      ),
                      Text(_correct ? 'Rätt!' : 'Fel. Svaret var $_answer'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _newProblem,
                        child: const Text('Nästa tal'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MathAiPage(
                      currentUser: widget.currentUser,
                      selectedChild: widget.selectedChild,
                      schoolYear: _schoolYear,
                    ),
                  ),
                ),
                icon: const Icon(Icons.psychology),
                label: const Text('AI – Läs och räkna'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
