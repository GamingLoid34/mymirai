import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/document_storage_upload.dart';
import '../data/document_repository.dart';
import '../models/document.dart';
import '../services/ai_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/friendly_errors.dart';
import 'document_detail_screen.dart';

/// Vilket steg som ska starta automatiskt när skärmen öppnas (VO-04 +-meny).
enum DocumentCreateInitialAction { pickFile, importLink, writeText }

class DocumentCreateFlowScreen extends StatefulWidget {
  const DocumentCreateFlowScreen({
    super.key,
    required this.repository,
    required this.ownerUid,
    this.initialAction,
    this.sharedFileBytes,
    this.sharedFileName,
    this.sharedUrl,
  });

  final DocumentRepository repository;
  final String ownerUid;
  final DocumentCreateInitialAction? initialAction;

  /// VO-10: fil delad från en annan app (t.ex. bild/PDF) — hoppar över filväljaren.
  final Uint8List? sharedFileBytes;
  final String? sharedFileName;

  /// VO-10: URL delad från en annan app — importeras automatiskt.
  final String? sharedUrl;

  @override
  State<DocumentCreateFlowScreen> createState() => _DocumentCreateFlowScreenState();
}

class _DocumentCreateFlowScreenState extends State<DocumentCreateFlowScreen> {
  final _titleCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _textFocus = FocusNode();
  final _ai = AiService();
  bool _saving = false;
  bool _summarizing = false;
  bool _uploading = false;
  bool _extracting = false;
  bool _importingUrl = false;
  String? _summary;

  /// Utkast-ID när bilaga har skapats (Firestore) före slutlig sparning.
  String? _draftId;
  DocumentAttachment? _attachment;
  String? _attachmentStorageUrl;

  @override
  void initState() {
    super.initState();
    _textFocus.addListener(_onTextFocusChanged);
    final sharedBytes = widget.sharedFileBytes;
    final sharedUrl = widget.sharedUrl?.trim();
    if (sharedBytes != null && sharedBytes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _uploadSharedFile(sharedBytes, widget.sharedFileName ?? 'fil'),
      );
    } else if (sharedUrl != null && sharedUrl.isNotEmpty) {
      _urlCtrl.text = sharedUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) => _importFromLink(skipDialog: true));
    } else {
      final action = widget.initialAction;
      if (action != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _runInitialAction(action));
      }
    }
  }

  Future<void> _runInitialAction(DocumentCreateInitialAction action) async {
    if (!mounted) return;
    switch (action) {
      case DocumentCreateInitialAction.pickFile:
        await _pickAndUploadAttachment();
      case DocumentCreateInitialAction.importLink:
        await _importFromLink();
      case DocumentCreateInitialAction.writeText:
        _textFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _textFocus.removeListener(_onTextFocusChanged);
    _textFocus.dispose();
    _titleCtrl.dispose();
    _textCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onTextFocusChanged() {
    if (_textFocus.hasFocus) return;
    final currentTitle = _titleCtrl.text.trim();
    if (currentTitle.isNotEmpty) return;
    final firstLine = _textCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return;
    setState(() {
      _titleCtrl.text = firstLine.length > 60 ? firstLine.substring(0, 60) : firstLine;
    });
  }

  String _sourceTypeForSave() {
    if (_attachment != null) return 'file';
    if (_urlCtrl.text.trim().isNotEmpty) return 'article';
    return 'text';
  }

  Future<void> _summarize() async {
    final text = _textCtrl.text.trim();
    if (text.length < 20 || _summarizing) return;
    setState(() => _summarizing = true);
    try {
      final s = await _ai.summarize(
        text,
        audience: SummarizeAudience.adult,
      );
      if (!mounted) return;
      setState(() {
        _summary = s;
        _summarizing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _summarizing = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att sammanfatta. Testa igen om en stund.',
        error: e,
      );
    }
  }

  static const _placeholderTitle = 'Nytt dokument';

  String _titleOrPlaceholder() {
    final t = _titleCtrl.text.trim();
    return t.isEmpty ? _placeholderTitle : t;
  }

  /// Filnamn utan ändelse, max 60 tecken — förslag när titeln saknas efter uppladdning.
  String _suggestedTitleFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = (dot > 0 ? fileName.substring(0, dot) : fileName).trim();
    if (base.isEmpty) return _placeholderTitle;
    return base.length > 60 ? base.substring(0, 60) : base;
  }

  Future<String> _ensureDraftForAttachment() async {
    if (_draftId != null) return _draftId!;
    final title = _titleOrPlaceholder();
    final now = DateTime.now();
    final id = await widget.repository.create(
      UserDocument(
        id: '',
        ownerUid: widget.ownerUid,
        title: title,
        extractedText: _textCtrl.text.trim().isEmpty ? null : _textCtrl.text.trim(),
        summary: _summary,
        sourceUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
        sourceType: 'file',
        createdAt: now,
        updatedAt: now,
      ),
    );
    setState(() => _draftId = id);
    return id;
  }

  Future<void> _pickAndUploadAttachment() async {
    if (_uploading) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.single;
    final rawBytes = pf.bytes;
    if (rawBytes == null || rawBytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kunde inte läsa filen. Försök igen eller välj en mindre fil.'),
        ),
      );
      return;
    }
    final fileName = pf.name.trim().isEmpty ? 'fil' : pf.name.trim();
    await _uploadBytesAsAttachment(Uint8List.fromList(rawBytes), fileName);
  }

  /// VO-10: samma uppladdningslogik som [_pickAndUploadAttachment], men för en
  /// fil som redan finns som bytes (delad från en annan app).
  Future<void> _uploadSharedFile(Uint8List bytes, String fileName) async {
    if (_uploading || !mounted) return;
    await _uploadBytesAsAttachment(bytes, fileName);
  }

  Future<void> _uploadBytesAsAttachment(Uint8List bytes, String fileName) async {
    setState(() => _uploading = true);
    try {
      final docId = await _ensureDraftForAttachment();
      final uploaded = await uploadDocumentAttachmentBytes(
        ownerUid: widget.ownerUid,
        documentId: docId,
        fileName: fileName,
        bytes: bytes,
      );
      final attach = DocumentAttachment(
        storagePath: uploaded.storagePath,
        fileName: fileName,
        sizeBytes: uploaded.sizeBytes,
        mimeType: uploaded.effectiveMimeType,
      );
      final currentTitle = _titleCtrl.text.trim();
      final suggestTitle = currentTitle.isEmpty || currentTitle == _placeholderTitle;
      final title = suggestTitle ? _suggestedTitleFromFileName(fileName) : currentTitle;
      final now = DateTime.now();
      await widget.repository.update(
        UserDocument(
          id: docId,
          ownerUid: widget.ownerUid,
          title: title,
          extractedText: _textCtrl.text.trim().isEmpty ? null : _textCtrl.text.trim(),
          summary: _summary,
          sourceUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
          attachment: attach,
          attachmentStorageUrl: uploaded.downloadUrl,
          sourceType: 'file',
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (!mounted) return;
      setState(() {
        if (suggestTitle) _titleCtrl.text = title;
        _attachment = attach;
        _attachmentStorageUrl = uploaded.downloadUrl;
        _uploading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      debugPrint('[DocumentCreate] upload hint: ${_storageErrorHint(e.code) ?? 'none'}');
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att ladda upp. Testa igen om en stund.',
        error: '${e.code}: ${e.message}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att ladda upp. Testa igen om en stund.',
        error: e,
      );
    }
  }

  /// Storage: [unauthorized] och [unauthenticated] — ofta regler ej deployade.
  ///
  /// [skipDialog] används av VO-10 (delad URL): [_urlCtrl] är redan ifylld
  /// från delningen, så användaren slipper bekräfta i en dialogruta igen.
  Future<void> _importFromLink({bool skipDialog = false}) async {
    if (_importingUrl || _saving) return;
    String raw;
    if (skipDialog) {
      raw = _urlCtrl.text.trim();
    } else {
      final ctrl = TextEditingController(text: _urlCtrl.text.trim());
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Importera från länk'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'https://…',
              labelText: 'Webbadress',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Hämta'),
            ),
          ],
        ),
      );
      raw = ctrl.text.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ctrl.dispose();
      });
      if (confirmed != true) return;
    }
    if (raw.length < 8 || !mounted) return;

    setState(() => _importingUrl = true);
    try {
      final got = await _ai.extractFromUrl(raw);
      if (!mounted) return;
      final t = got.title.trim();
      setState(() {
        _draftId = null;
        _attachment = null;
        _attachmentStorageUrl = null;
        _urlCtrl.text = got.sourceUrl;
        _textCtrl.text = got.text;
        if (t.isNotEmpty) {
          _titleCtrl.text = t;
        }
        _importingUrl = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Artikeln är inläst. Du kan sammanfatta och spara.')),
      );
    } on AiAuthException catch (e) {
      if (mounted) {
        setState(() => _importingUrl = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on AiInvalidInputException catch (e) {
      if (mounted) {
        setState(() => _importingUrl = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on AiUnavailableException catch (e) {
      if (mounted) {
        setState(() => _importingUrl = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e, st) {
      debugPrint('$st');
      if (mounted) {
        setState(() => _importingUrl = false);
        showFriendlySnack(
          context,
          'Hoppsan – det gick inte att importera länken. Testa igen om en stund.',
          error: e,
        );
      }
    }
  }

  String? _storageErrorHint(String code) {
    final c = code.toLowerCase();
    if (c.contains('unauthorized') || c.contains('permission-denied')) {
      return 'Storage nekar uppladdning. Deploya firebase/storage.rules för '
          'sökvägen documents/{uid}/… (firebase deploy --only storage '
          '--project=la-familia-5d9f5) eller uppdatera reglerna i Console.';
    }
    if (c.contains('unauthenticated')) {
      return 'Inte autentiserad mot Storage. Logga ut och in igen.';
    }
    return null;
  }

  Future<void> _extractFromAttachment() async {
    if (_extracting || _draftId == null || _attachment == null) return;
    setState(() => _extracting = true);
    try {
      final synced = await widget.repository.getById(_draftId!);
      if (!mounted) return;
      if (synced == null) {
        setState(() => _extracting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Utkastet hittades inte i Firestore. Om du växlat konto eller nät är '
              'ostabilt: vänta och prova igen.',
            ),
          ),
        );
        return;
      }
      if (synced.attachment == null ||
          synced.attachmentStorageUrl == null ||
          synced.attachmentStorageUrl!.isEmpty) {
        setState(() => _extracting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Molnet saknar bifogade fält för det här utkastet. Ladda upp filen igen '
              'sedan välj Extrahera.',
            ),
          ),
        );
        return;
      }

      final extracted = await _ai.extractFromDocument(_draftId!);
      if (!mounted) return;
      _textCtrl.text = extracted.text;
      if (extracted.warning == 'no_text_layer' && extracted.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF:en saknar textlager (troligen skannad). Ingen text kunde extraheras.',
            ),
          ),
        );
      }
      final title = _titleOrPlaceholder();
      final now = DateTime.now();
      await widget.repository.update(
        UserDocument(
          id: _draftId!,
          ownerUid: widget.ownerUid,
          title: title,
          extractedText: extracted.text.trim().isEmpty ? null : extracted.text.trim(),
          summary: _summary,
          sourceUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
          attachment: _attachment,
          attachmentStorageUrl: _attachmentStorageUrl,
          sourceType: 'file',
          createdAt: now,
          updatedAt: now,
        ),
      );
      setState(() => _extracting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _extracting = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att extrahera texten. Testa igen om en stund.',
        error: e,
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleOrPlaceholder();
    setState(() => _saving = true);
    try {
      late final String id;
      final now = DateTime.now();

      if (_draftId != null) {
        id = _draftId!;
        await widget.repository.update(
          UserDocument(
            id: id,
            ownerUid: widget.ownerUid,
            title: title,
            extractedText: _textCtrl.text.trim().isEmpty ? null : _textCtrl.text.trim(),
            summary: _summary,
            sourceUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
            attachment: _attachment,
            attachmentStorageUrl: _attachmentStorageUrl,
            sourceType: _sourceTypeForSave(),
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        id = await widget.repository.create(
          UserDocument(
            id: '',
            ownerUid: widget.ownerUid,
            title: title,
            extractedText: _textCtrl.text.trim().isEmpty ? null : _textCtrl.text.trim(),
            summary: _summary,
            sourceUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
            attachment: null,
            attachmentStorageUrl: null,
            sourceType: _sourceTypeForSave(),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DocumentDetailScreen(
            repository: widget.repository,
            ownerUid: widget.ownerUid,
            documentId: id,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara dokumentet. Testa igen om en stund.',
        error: e,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final attachLabel = _attachment?.fileName;
    return Scaffold(
      appBar: AppBar(title: const Text('Nytt dokument')),
      body: Center(
        child: MiraiAdaptiveBox(
          child: ListView(
            padding: const EdgeInsets.all(MiraiTokens.spaceLg),
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Titel', border: OutlineInputBorder()),
              ),
              const SizedBox(height: MiraiTokens.spaceSm),
              Text(
                'PDF · Word · bild, eller klistra in en artikellänk.',
                style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
              ),
              const SizedBox(height: MiraiTokens.spaceSm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_uploading || _saving || _importingUrl)
                          ? null
                          : _pickAndUploadAttachment,
                      icon: _uploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file_rounded),
                      label: Text(
                        _uploading ? 'Laddar upp...' : 'Ladda upp fil',
                      ),
                    ),
                  ),
                  const SizedBox(width: MiraiTokens.spaceSm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_uploading || _saving || _importingUrl)
                          ? null
                          : _importFromLink,
                      icon: _importingUrl
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link_rounded),
                      label: Text(_importingUrl ? 'Hämtar…' : 'Importera länk'),
                    ),
                  ),
                ],
              ),
              if (_urlCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: MiraiTokens.spaceXs),
                Text(
                  'Källa: ${_urlCtrl.text.trim()}',
                  style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                ),
              ],
              if ((attachLabel ?? '').isNotEmpty) ...[
                const SizedBox(height: MiraiTokens.spaceXs),
                Text(
                  'Bifogad: $attachLabel',
                  style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                ),
              ],
              if (_draftId != null && _attachment != null) ...[
                const SizedBox(height: MiraiTokens.spaceSm),
                if (kUseFirestoreHomework)
                  FilledButton.icon(
                    onPressed: (_extracting || _summarizing || _saving) ? null : _extractFromAttachment,
                    icon: _extracting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.text_snippet_rounded),
                    label: Text(_extracting ? 'Extraherar...' : 'Extrahera text från bilaga'),
                  )
                else
                  Text(
                    'Textextrahering från bilagor kräver molnläge (Firestore). '
                    'Skriv eller klistra in texten manuellt i demo-läget.',
                    style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                  ),
              ],
              const SizedBox(height: MiraiTokens.spaceSm),
              TextField(
                controller: _textCtrl,
                focusNode: _textFocus,
                minLines: 8,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'Klistra text',
                  hintText: 'Klistra in artikel eller dokumenttext…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: MiraiTokens.spaceSm),
              FilledButton.tonalIcon(
                onPressed: _summarizing ? null : _summarize,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(_summarizing ? 'Sammanfattar...' : 'Sammanfatta'),
              ),
              if ((_summary ?? '').isNotEmpty) ...[
                const SizedBox(height: MiraiTokens.spaceSm),
                Container(
                  padding: const EdgeInsets.all(MiraiTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: MiraiTokens.bgRaised,
                    borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                    border: Border.all(color: MiraiTokens.borderSubtle),
                  ),
                  child: Text(
                    _summary!,
                    style: tt.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MiraiTokens.spaceLg),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Spara dokument'),
          ),
        ),
      ),
    );
  }
}
