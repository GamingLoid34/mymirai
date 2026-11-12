import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../data/vardag_letters.dart';
import '../services/school_letter.dart';

class VardagLetterPicker extends StatefulWidget {
  const VardagLetterPicker({super.key});
  @override
  State<VardagLetterPicker> createState() => _VardagLetterPickerState();
}

class _VardagLetterPickerState extends State<VardagLetterPicker> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  List<SchoolLetter>? _letters;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_loading) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Fyll i e-postadress och lösenord till Vardag.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final letters = await VardagLetters.fetch(_email.text, _password.text);
      if (mounted) {
        setState(() {
          _password.clear();
          _letters = letters;
        });
      }
    } catch (error) {
      if (kDebugMode) {
        final code = error is FirebaseException
            ? '${error.plugin}/${error.code}'
            : error.runtimeType.toString();
        debugPrint('[Vardag] Hämtningen misslyckades ($code)');
      }
      var message =
          'Det gick inte att hämta breven. Kontrollera anslutningen och försök igen.';
      if (error is StateError) message = error.message;
      if (error is FirebaseException) {
        if ([
          'invalid-credential',
          'invalid-email',
          'user-not-found',
          'wrong-password',
        ].contains(error.code)) {
          message =
              'Inloggningen misslyckades. Kontrollera e-post och lösenord.';
        } else if (error.code == 'permission-denied') {
          message =
              'Kontot saknar behörighet att läsa familjens skolnyheter i Vardag.';
        } else if (error.code == 'too-many-requests') {
          message =
              'För många försök. Vänta en stund eller klistra in ett brev.';
        }
      }
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final letters = _letters;
    return Scaffold(
      appBar: AppBar(title: const Text('Skolnyheter i Vardag')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (letters == null) ...[
                  Text(
                    'Logga in med ditt vuxenkonto i Vardag',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Välj sedan ett SchoolSoft-brev. Endast läxorna du godkänner sparas på den här enheten.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'E-post i Vardag',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Lösenord'),
                    onSubmitted: (_) => _fetch(),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _fetch,
                    child: Text(
                      _loading ? 'Hämtar brev…' : 'Hämta skolnyheter',
                    ),
                  ),
                ] else if (letters.isEmpty)
                  const Text(
                    'Inga SchoolSoft-brev hittades. Kontrollera skolnyheterna i Vardags inkorg eller gå tillbaka och klistra in ett brev.',
                  )
                else ...[
                  Text(
                    'Välj ett brev',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final l in letters)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.title),
                      subtitle: l.publishedAt == null
                          ? null
                          : Text(
                              '${l.publishedAt!.day}/${l.publishedAt!.month} ${l.publishedAt!.year}',
                            ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, l),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
