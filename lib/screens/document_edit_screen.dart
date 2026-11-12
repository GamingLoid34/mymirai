import 'package:flutter/material.dart';

import '../data/document_repository.dart';
import '../models/document.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';

class DocumentEditScreen extends StatefulWidget {
  const DocumentEditScreen({
    super.key,
    required this.repository,
    required this.initial,
  });

  final DocumentRepository repository;
  final UserDocument initial;

  @override
  State<DocumentEditScreen> createState() => _DocumentEditScreenState();
}

class _DocumentEditScreenState extends State<DocumentEditScreen> {
  final _titleCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _extractedCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _titleCtrl.text = d.title;
    _urlCtrl.text = d.sourceUrl ?? '';
    _summaryCtrl.text = d.summary ?? '';
    _extractedCtrl.text = d.extractedText ?? '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _summaryCtrl.dispose();
    _extractedCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);

    final urlT = _urlCtrl.text.trim();
    final summaryT = _summaryCtrl.text.trim();
    final extractedT = _extractedCtrl.text.trim();

    final next = widget.initial.copyWith(
      title: title,
      clearSourceUrl: urlT.isEmpty,
      sourceUrl: urlT.isEmpty ? null : urlT,
      clearSummary: summaryT.isEmpty,
      summary: summaryT.isEmpty ? null : summaryT,
      clearExtractedText: extractedT.isEmpty,
      extractedText: extractedT.isEmpty ? null : extractedT,
    );

    try {
      await widget.repository.update(next);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara. Testa igen om en stund.',
        error: e,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Redigera dokument')),
      body: SafeArea(
        child: Center(
          child: MiraiAdaptiveBox(
            child: ListView(
              padding: const EdgeInsets.all(MiraiTokens.spaceLg),
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Titel',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: MiraiTokens.spaceSm),
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Källa (URL, valfritt)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: MiraiTokens.spaceSm),
                Text('Sammanfattning', style: tt.labelLarge),
                const SizedBox(height: MiraiTokens.spaceXs),
                TextField(
                  controller: _summaryCtrl,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: 'Manuell eller AI-sammanfattning…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: MiraiTokens.spaceMd),
                Text('Extraherad text', style: tt.labelLarge),
                const SizedBox(height: MiraiTokens.spaceXs),
                TextField(
                  controller: _extractedCtrl,
                  minLines: 6,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    hintText: 'Råtext ur fil eller inklistrat…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: MiraiTokens.spaceLg),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Spara'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
