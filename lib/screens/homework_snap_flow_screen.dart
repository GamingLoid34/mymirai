import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../data/deck_repository.dart';
import '../data/homework_repository.dart';
import '../models/homework_item.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/snap_pipeline_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import '../util/homework_type_labels.dart';
import '../util/subject_suggestions.dart';
import '../widgets/subject_field.dart';
import 'homework_detail_screen.dart';

const _kMaxAttachments = 8;

enum SnapIntent { homework, quiz }

class _SnapFile {
  _SnapFile({required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;
  String get mime => _guessMime(fileName);
}

enum _StepStatus { waiting, running, done, failed }

class _PipelineStep {
  _PipelineStep(this.label);
  final String label;
  _StepStatus status = _StepStatus.waiting;
  String? errorMsg;
}

class HomeworkSnapFlowScreen extends StatefulWidget {
  const HomeworkSnapFlowScreen({
    super.key,
    required this.repository,
    this.deckRepository,
    required this.familyId,
    required this.assignedToUserId,
    this.authService,
    this.intent = SnapIntent.homework,
  });

  final HomeworkRepository repository;
  final DeckRepository? deckRepository;
  final String familyId;
  final String assignedToUserId;
  final AuthService? authService;
  final SnapIntent intent;

  @override
  State<HomeworkSnapFlowScreen> createState() => _HomeworkSnapFlowScreenState();
}

class _HomeworkSnapFlowScreenState extends State<HomeworkSnapFlowScreen> {
  final _picker = ImagePicker();

  final List<_SnapFile> _files = [];

  bool _pipelineRunning = false;
  bool _pipelineDone = false;
  String? _savedHomeworkId;

  final List<_PipelineStep> _steps = [
    _PipelineStep('Sparar läxan …'),
    _PipelineStep('Läser din läxa 👀'),
    _PipelineStep('Lägger ihop allt …'),
    _PipelineStep('Nästan klar – föreslår titel och datum …'),
  ];

  final _titleCtrl = TextEditingController(text: 'Ny läxa');
  final _subjectCtrl = TextEditingController(text: 'Ämne');
  DateTime? _dueAt;
  String _homeworkType = 'text';
  HomeworkMetadataSuggestion? _suggestion;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    SnapPipelineService.instance.addListener(_onPipelineServiceChanged);
    if (widget.intent == SnapIntent.quiz) {
      _titleCtrl.text = 'Glosor';
      _homeworkType = 'vocabulary';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
  }

  @override
  void dispose() {
    SnapPipelineService.instance.removeListener(_onPipelineServiceChanged);
    _titleCtrl.dispose();
    _subjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    if (_files.length >= _kMaxAttachments) return;
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 93,
    );
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() => _files.add(_SnapFile(bytes: bytes, fileName: image.name)));
  }

  Future<void> _pickGallery() async {
    if (_files.length >= _kMaxAttachments) {
      _showMaxSnackbar();
      return;
    }
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 93,
    );
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() => _files.add(_SnapFile(bytes: bytes, fileName: image.name)));
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
    );
    if (r == null || r.files.isEmpty) return;
    var hitLimit = false;
    setState(() {
      for (final f in r.files) {
        if (_files.length >= _kMaxAttachments) {
          hitLimit = true;
          break;
        }
        if (f.bytes != null && f.name.trim().isNotEmpty) {
          _files.add(_SnapFile(bytes: f.bytes!, fileName: f.name));
        }
      }
    });
    if (hitLimit && mounted) _showMaxSnackbar();
  }

  void _showMaxSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Max $_kMaxAttachments bilagor – några hoppades över.')),
    );
  }

  void _removeAt(int index) {
    if (index < 0 || index >= _files.length) return;
    setState(() => _files.removeAt(index));
  }

  Future<void> _startPipeline() async {
    if (_files.isEmpty || _pipelineRunning || !kUseFirestoreHomework) return;

    setState(() {
      _pipelineRunning = true;
      for (final s in _steps) {
        s.status = _StepStatus.waiting;
        s.errorMsg = null;
      }
      _steps[0].status = _StepStatus.running;
    });

    final pipelineFiles = _files
        .map((f) => SnapPipelineFile(
              bytes: f.bytes,
              fileName: f.fileName,
              mime: f.mime,
            ))
        .toList();

    try {
      final homeworkId = await SnapPipelineService.instance.start(
        repository: widget.repository,
        familyId: widget.familyId,
        assignedToUserId: widget.assignedToUserId,
        files: pipelineFiles,
        intent: widget.intent,
        onDraftCreated: (id) {
          if (mounted) setState(() => _savedHomeworkId = id);
        },
      );
      if (mounted) setState(() => _savedHomeworkId = homeworkId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _pipelineRunning = false;
          _steps[0].status = _StepStatus.failed;
          _steps[0].errorMsg = 'Kunde inte spara: $e';
        });
      }
    }
  }

  void _onPipelineServiceChanged() {
    final id = _savedHomeworkId;
    if (id == null) return;
    final task = SnapPipelineService.instance.getTask(id);
    if (task == null || !mounted) return;

    setState(() {
      for (var i = 0; i < _steps.length; i++) {
        if (i < task.currentStep) {
          _steps[i].status = _StepStatus.done;
          _steps[i].errorMsg = null;
        } else if (i == task.currentStep) {
          _steps[i].status = task.isFailed
              ? _StepStatus.failed
              : (task.isDone ? _StepStatus.done : _StepStatus.running);
          _steps[i].errorMsg = task.errorMsg;
        } else {
          _steps[i].status = _StepStatus.waiting;
          _steps[i].errorMsg = null;
        }
      }

      if (task.isDone) {
        _pipelineRunning = false;
        _pipelineDone = true;
        if (task.item != null) {
          _titleCtrl.text = task.item!.title;
          _subjectCtrl.text = task.item!.subject;
          _dueAt = task.item!.dueAt;
          _homeworkType = task.item!.homeworkType;
        }
        _suggestion = task.suggestion;
      } else if (task.isFailed) {
        _pipelineRunning = false;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDate: _dueAt ?? DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _dueAt = picked);
  }

  Future<void> _saveHomework() async {
    final id = _savedHomeworkId;
    if (id == null || _saving) return;
    setState(() => _saving = true);
    try {
      final snapList = await widget.repository
          .watchForFamily(
            familyId: widget.familyId,
            assignedToUserId: widget.assignedToUserId,
          )
          .first;
      HomeworkItem? current;
      for (final h in snapList) {
        if (h.id == id) {
          current = h;
          break;
        }
      }
      if (current == null || !mounted) {
        setState(() => _saving = false);
        return;
      }
      final updated = current.copyWith(
        title: _titleCtrl.text.trim().isEmpty ? 'Ny läxa' : _titleCtrl.text.trim(),
        subject: _subjectCtrl.text.trim().isEmpty ? 'Ämne' : _subjectCtrl.text.trim(),
        dueAt: _dueAt,
        homeworkType: _homeworkType,
      );
      await widget.repository.update(updated);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeworkDetailScreen(
            repository: widget.repository,
            deckRepository: widget.deckRepository,
            familyId: widget.familyId,
            assignedToUserId: widget.assignedToUserId,
            homeworkId: id,
            autoPipeline: true,
            autoStartQuiz: widget.intent == SnapIntent.quiz,
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara läxan. Testa igen om en stund.',
        error: e,
      );
    }
  }

  Future<void> _showAbortDialog() async {
    final id = _savedHomeworkId;
    if (id == null) {
      Navigator.of(context).pop();
      return;
    }

    if (_pipelineRunning) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Läxan sparas i bakgrunden'),
          content: const Text(
            'Analysen fortsätter i bakgrunden. Du får en notis när läxan är klar!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('close'),
              child: const Text('Gå till startsidan'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('open'),
              child: const Text('Öppna läxan'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'open') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => HomeworkDetailScreen(
              repository: widget.repository,
              deckRepository: widget.deckRepository,
              familyId: widget.familyId,
              assignedToUserId: widget.assignedToUserId,
              homeworkId: id,
              autoStartQuiz: widget.intent == SnapIntent.quiz,
              authService: widget.authService,
            ),
          ),
        );
      } else if (choice == 'close') {
        Navigator.of(context).pop();
      }
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Läxan är sparad med dina foton'),
        content: const Text('Vill du öppna läxan eller stänga?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('close'),
            child: const Text('Stäng'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('open'),
            child: const Text('Öppna läxan'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'open') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeworkDetailScreen(
            repository: widget.repository,
            deckRepository: widget.deckRepository,
            familyId: widget.familyId,
            assignedToUserId: widget.assignedToUserId,
            homeworkId: id,
            autoStartQuiz: widget.intent == SnapIntent.quiz,
            authService: widget.authService,
          ),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showAbortDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _showAbortDialog,
          ),
          title: const Text('Fota läxan'),
        ),
        body: SafeArea(
          child: Center(
            child: MiraiAdaptiveBox(
              child: _pipelineDone
                  ? _ConfirmView(
                      titleCtrl: _titleCtrl,
                      subjectCtrl: _subjectCtrl,
                      dueAt: _dueAt,
                      homeworkType: _homeworkType,
                      suggestion: _suggestion,
                      intent: widget.intent,
                      saving: _saving,
                      onPickDate: _pickDate,
                      onClearDate: () => setState(() => _dueAt = null),
                      onChangeType: (t) => setState(() => _homeworkType = t),
                      onSave: _saveHomework,
                      familyId: widget.familyId,
                      assignedToUserId: widget.assignedToUserId,
                      repository: widget.repository,
                    )
                  : _pipelineRunning
                      ? _PipelineView(steps: _steps)
                      : _PhotoView(
                          files: _files,
                          onCamera: _openCamera,
                          onGallery: _pickGallery,
                          onFile: _pickFile,
                          onRemove: _removeAt,
                          onStartPipeline: kUseFirestoreHomework
                              ? (_files.isNotEmpty ? _startPipeline : null)
                              : null,
                          firebaseDisabled: !kUseFirestoreHomework,
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

// -- Foto-vy ------------------------------------------------------------------

class _PhotoView extends StatelessWidget {
  const _PhotoView({
    required this.files,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    required this.onRemove,
    required this.onStartPipeline,
    required this.firebaseDisabled,
  });

  final List<_SnapFile> files;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final void Function(int) onRemove;
  final VoidCallback? onStartPipeline;
  final bool firebaseDisabled;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
      children: [
        Text(
          'Fota läxlappen',
          style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: MiraiTokens.spaceXs),
        Text(
          'Ta ett foto eller välj en fil – jag läser texten åt dig.',
          style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
        ),
        const SizedBox(height: MiraiTokens.spaceLg),
        Row(
          children: [
            Expanded(
              child: _BigButton(
                icon: Icons.camera_alt_outlined,
                label: 'Ta foto',
                onTap: onCamera,
              ),
            ),
            const SizedBox(width: MiraiTokens.spaceSm),
            Expanded(
              child: _BigButton(
                icon: Icons.photo_library_outlined,
                label: 'Välj bild',
                onTap: onGallery,
              ),
            ),
            const SizedBox(width: MiraiTokens.spaceSm),
            Expanded(
              child: _BigButton(
                icon: Icons.attach_file_rounded,
                label: 'Välj fil',
                onTap: onFile,
              ),
            ),
          ],
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: MiraiTokens.spaceMd),
          ...List.generate(files.length, (i) {
            final f = files[i];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.image_outlined,
                size: 20,
                color: MiraiTokens.textSecondary,
              ),
              title: Text(
                f.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => onRemove(i),
                tooltip: 'Ta bort',
              ),
            );
          }),
        ],
        const SizedBox(height: MiraiTokens.spaceLg),
        Tooltip(
          message: firebaseDisabled ? 'Kraver Firebase' : '',
          child: FilledButton.icon(
            onPressed: onStartPipeline,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Läs läxan'),
          ),
        ),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: MiraiTokens.bgRaised,
      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            border: Border.all(
              color: MiraiTokens.borderSubtle,
              width: MiraiTokens.borderThin,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: MiraiTokens.accent, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: tt.labelSmall?.copyWith(color: MiraiTokens.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- Pipeline-vy --------------------------------------------------------------

class _PipelineView extends StatelessWidget {
  const _PipelineView({required this.steps});
  final List<_PipelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
      children: [
        Text(
          'Läser läxan …',
          style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: MiraiTokens.spaceLg),
        for (final s in steps) ...[
          _StepRow(step: s),
          const SizedBox(height: MiraiTokens.spaceSm),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});
  final _PipelineStep step;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget icon;
    switch (step.status) {
      case _StepStatus.waiting:
        icon = const Icon(
          Icons.radio_button_unchecked_rounded,
          size: 20,
          color: MiraiTokens.textTertiary,
        );
      case _StepStatus.running:
        icon = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _StepStatus.done:
        icon = const Icon(
          Icons.check_circle_rounded,
          size: 20,
          color: MiraiTokens.success,
        );
      case _StepStatus.failed:
        icon = const Icon(
          Icons.error_outline_rounded,
          size: 20,
          color: MiraiTokens.danger,
        );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        const SizedBox(width: MiraiTokens.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.label, style: tt.bodyMedium),
              if (step.errorMsg != null)
                Text(
                  step.errorMsg!,
                  style: tt.bodySmall?.copyWith(color: MiraiTokens.danger),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// -- Bekraftelse-vy -----------------------------------------------------------

class _ConfirmView extends StatelessWidget {
  const _ConfirmView({
    required this.titleCtrl,
    required this.subjectCtrl,
    required this.dueAt,
    required this.homeworkType,
    this.suggestion,
    this.intent = SnapIntent.homework,
    required this.saving,
    required this.onPickDate,
    required this.onClearDate,
    required this.onChangeType,
    required this.onSave,
    required this.familyId,
    required this.assignedToUserId,
    required this.repository,
  });

  final TextEditingController titleCtrl;
  final TextEditingController subjectCtrl;
  final DateTime? dueAt;
  final String homeworkType;
  final HomeworkMetadataSuggestion? suggestion;
  final SnapIntent intent;
  final bool saving;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final void Function(String) onChangeType;
  final VoidCallback onSave;
  final String familyId;
  final String assignedToUserId;
  final HomeworkRepository repository;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final saveLabel = intent == SnapIntent.quiz
        ? 'Spara och starta förhör'
        : (homeworkType == 'vocabulary'
            ? 'Spara och gör förhörskort'
            : 'Spara läxan');

    return ListView(
      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
      children: [
        Text(
          'Stämmer det här?',
          style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: MiraiTokens.spaceXs),
        Text(
          'AI har föreslagit titel, ämne och datum – ändra om det behövs.',
          style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
        ),
        const SizedBox(height: MiraiTokens.spaceLg),
        _FieldBox(
          label: 'Titel',
          hint: 'T.ex. Glosor v.38 - engelska',
          controller: titleCtrl,
        ),
        const SizedBox(height: MiraiTokens.spaceSm),
        StreamBuilder<List<HomeworkItem>>(
          stream: repository.watchForFamily(
            familyId: familyId,
            assignedToUserId: assignedToUserId,
          ),
          builder: (context, snap) {
            final raw = snap.data ?? const <HomeworkItem>[];
            final list = kUseFirestoreHomework
                ? raw.where((h) => !h.id.startsWith('dev-')).toList()
                : raw;
            return SubjectField(
              controller: subjectCtrl,
              options: mergedSubjectOptions(list),
              label: 'Ämne',
              hint: 'T.ex. Engelska',
            );
          },
        ),
        const SizedBox(height: MiraiTokens.spaceMd),
        ListTile(
          tileColor: MiraiTokens.bgRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
            side: const BorderSide(color: MiraiTokens.borderSubtle),
          ),
          leading: const Icon(Icons.calendar_today_outlined),
          title: Text(
            dueAt == null
                ? 'Välj inlämningsdatum'
                : 'Inlämning: ${dueAt!.day}/${dueAt!.month}/${dueAt!.year}',
          ),
          onTap: onPickDate,
        ),
        if (dueAt != null) ...[
          const SizedBox(height: MiraiTokens.spaceXs),
          TextButton(
            onPressed: onClearDate,
            child: const Text('Ingen deadline'),
          ),
        ],
        const SizedBox(height: MiraiTokens.spaceMd),
        if (suggestion != null && suggestion!.confidence >= 0.6) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(MiraiTokens.spaceMd),
            decoration: BoxDecoration(
              color: const Color(0x26FFC107),
              borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
              border: Border.all(color: const Color(0x66FFA000)),
            ),
            child: Text(
              intent == SnapIntent.quiz && suggestion!.homeworkType != 'vocabulary'
                  ? 'AI:n tror att det här är ${homeworkTypeLabel(suggestion!.homeworkType).toLowerCase()} – byt typ nedan om det stämmer.'
                  : suggestion!.homeworkType == 'vocabulary'
                      ? 'Det här ser ut som glosor – vi gör förhörskort av dem. 🎴'
                      : suggestion!.homeworkType == 'math'
                          ? 'Det här ser ut som matteuppgifter – vi kan förklara och variera dem.'
                          : 'Det här ser ut som vanlig textläxa.',
              style: tt.bodySmall?.copyWith(
                color: MiraiTokens.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: MiraiTokens.spaceMd),
        ],
        Text(
          'TYP',
          style: tt.labelSmall?.copyWith(
            letterSpacing: 0.5,
            color: MiraiTokens.textTertiary,
          ),
        ),
        const SizedBox(height: MiraiTokens.spaceXs),
        Wrap(
          spacing: MiraiTokens.spaceSm,
          children: [
            ChoiceChip(
              label: const Text('Text'),
              selected: homeworkType == 'text',
              onSelected: (s) {
                if (s) onChangeType('text');
              },
            ),
            ChoiceChip(
              label: const Text('Glosor'),
              selected: homeworkType == 'vocabulary',
              onSelected: (s) {
                if (s) onChangeType('vocabulary');
              },
            ),
            ChoiceChip(
              label: const Text('Matte'),
              selected: homeworkType == 'math',
              onSelected: (s) {
                if (s) onChangeType('math');
              },
            ),
          ],
        ),
        if (homeworkTypeExplanation(homeworkType).isNotEmpty) ...[
          const SizedBox(height: MiraiTokens.spaceXs),
          Text(
            homeworkTypeExplanation(homeworkType),
            style: tt.bodySmall?.copyWith(
              color: MiraiTokens.textTertiary,
            ),
          ),
        ],
        const SizedBox(height: MiraiTokens.spaceLg),
        FilledButton(
          onPressed: saving ? null : onSave,
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(saveLabel),
        ),
      ],
    );
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({
    required this.label,
    required this.hint,
    required this.controller,
  });
  final String label;
  final String hint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MiraiTokens.bgRaised,
        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
        ),
      ),
    );
  }
}

String _guessMime(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}





