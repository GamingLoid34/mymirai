import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_mirai/core/app_theme.dart';
import 'package:my_mirai/core/models.dart';
import 'package:my_mirai/services/groq_service.dart';
import 'package:my_mirai/config/app_config.dart' as _AppConfig;

/// Läx-sidan: text, foto (OCR), .pptx-uppladdning, TTS, AI-verktyg.
class WorkPage extends StatefulWidget {
  final AppUser currentUser;
  final AppUser? selectedChild;

  const WorkPage({super.key, required this.currentUser, this.selectedChild});

  @override
  State<WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<WorkPage> {
  final _textController = TextEditingController();
  final _titleController = TextEditingController();
  final _flutterTts = FlutterTts();
  bool _ttsMuted = false;
  String? _aiSummary;
  List<String> _substeps = [];
  List<Flashcard> _flashcards = [];
  String? _selectedSubject;
  String _languageCode = 'sv';
  bool _loading = false;
  String? _error;

  static String get _groqApiKey => _AppConfig.AppConfig.groqApiKey;

  @override
  void initState() {
    super.initState();
    _flutterTts.setLanguage('sv-SE');
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.camera);
    if (img == null || !mounted) return;
    final bytes = await img.readAsBytes();
    final base64 = base64Encode(bytes);
    setState(() {
      _textController.text += '\n\n[Bild inlagd – OCR kommer i nästa steg]';
      // TODO: Anropa OCR API (t.ex. Google Vision eller Groq med bild) för att extrahera text
    });
  }

  Future<void> _pickPptx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pptx'],
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) return;
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final texts = <String>[];
      for (final entry in archive) {
        if (entry.name.endsWith('.xml') && entry.name.contains('slide')) {
          final content = utf8.decode(entry.content as List<int>);
          final text = content.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
          if (text.isNotEmpty) texts.add(text);
        }
      }
      setState(() {
        _textController.text = texts.join('\n\n');
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunde inte läsa .pptx: $e')));
      }
    }
  }

  Future<void> _speak() async {
    if (_ttsMuted) return;
    final text = _textController.text;
    if (text.isEmpty) return;
    await _flutterTts.speak(text);
  }

  Future<void> _aiSummarize() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Skriv in text först')));
      return;
    }
    if (_groqApiKey.isEmpty) {
      setState(() => _error = 'Groq API-nyckel saknas. Sätt GROQ_API_KEY.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _aiSummary = null;
    });
    try {
      final groq = GroqService(apiKey: _groqApiKey);
      final summary = await groq.summarize(text, languageCode: _languageCode);
      if (mounted) setState(() {
        _aiSummary = summary;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'AI-fel: $e';
        _loading = false;
      });
    }
  }

  Future<void> _aiSubsteps() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_groqApiKey.isEmpty) {
      setState(() => _error = 'Groq API-nyckel saknas.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final groq = GroqService(apiKey: _groqApiKey);
      final steps = await groq.createSubsteps(text);
      if (mounted) setState(() {
        _substeps = steps;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'AI-fel: $e';
        _loading = false;
      });
    }
  }

  Future<void> _aiStudyQuestions() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_groqApiKey.isEmpty) {
      setState(() => _error = 'Groq API-nyckel saknas.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final groq = GroqService(apiKey: _groqApiKey);
      final pairs = await groq.createStudyQuestions(text);
      if (mounted) setState(() {
        _flashcards.addAll(pairs.map((p) => Flashcard(front: p['front'] ?? '', back: p['back'] ?? '')));
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'AI-fel: $e';
        _loading = false;
      });
    }
  }

  Future<void> _aiGlosor() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_groqApiKey.isEmpty) {
      setState(() => _error = 'Groq API-nyckel saknas.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final groq = GroqService(apiKey: _groqApiKey);
      final pairs = await groq.createFlashcards(text, languageCode: _languageCode);
      if (mounted) setState(() {
        _flashcards.addAll(pairs.map((p) => Flashcard(front: p['front'] ?? '', back: p['back'] ?? '')));
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'AI-fel: $e';
        _loading = false;
      });
    }
  }

  Future<void> _saveHomework() async {
    final title = _titleController.text.trim();
    final text = _textController.text.trim();
    if (title.isEmpty || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fyll i titel och text')));
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('homeworks').add({
        'title': title,
        'subject': _selectedSubject ?? 'Övrigt',
        'originalText': text,
        'flashcards': _flashcards.map((f) => f.toMap()).toList(),
        'aiSummary': _aiSummary,
        'substeps': _substeps,
        'imagesBase64': <String>[],
        'languageCode': _languageCode,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Läxa sparad!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Läxor')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient(context)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Titel'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Text (eller använd kamera/pptx nedan)',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(onPressed: _pickImage, icon: const Icon(Icons.camera_alt), tooltip: 'Foto'),
                  IconButton(onPressed: _pickPptx, icon: const Icon(Icons.slideshow), tooltip: 'Ladda upp .pptx'),
                  IconButton(onPressed: _speak, icon: const Icon(Icons.volume_up), tooltip: 'Lyssna (TTS)'),
                ],
              ),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(onPressed: _loading ? null : _aiSummarize, icon: const Icon(Icons.summarize, size: 18), label: const Text('AI sammanfatta')),
                  FilledButton.icon(onPressed: _loading ? null : _aiSubsteps, icon: const Icon(Icons.checklist, size: 18), label: const Text('Checklista')),
                  FilledButton.icon(onPressed: _loading ? null : _aiStudyQuestions, icon: const Icon(Icons.quiz, size: 18), label: const Text('Frågor')),
                  FilledButton.icon(onPressed: _loading ? null : _aiGlosor, icon: const Icon(Icons.translate, size: 18), label: const Text('Glosor')),
                ],
              ),
              if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              if (_aiSummary != null) ...[
                const SizedBox(height: 16),
                Text('Sammanfattning', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppTheme.glassCard(context: context),
                  child: MarkdownBody(data: _aiSummary!),
                ),
              ],
              if (_substeps.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Checklista', style: Theme.of(context).textTheme.titleMedium),
                ..._substeps.asMap().entries.map((e) => CheckboxListTile(
                  value: false,
                  onChanged: (_) {},
                  title: Text('${e.key + 1}. ${e.value}'),
                  controlAffinity: ListTileControlAffinity.leading,
                )),
              ],
              if (_flashcards.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Kort (${_flashcards.length})', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                ..._flashcards.take(5).map((f) => ListTile(
                  title: Text(f.front),
                  subtitle: Text(f.back),
                )),
                if (_flashcards.length > 5) Text('... och ${_flashcards.length - 5} till'),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: _loading ? null : _saveHomework, child: const Text('Spara läxa')),
            ],
          ),
        ),
      ),
    );
  }
}
