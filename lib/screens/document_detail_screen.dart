import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/document_repository.dart';
import '../data/firestore_listening_stats_repository.dart';
import '../models/document.dart';
import '../services/ai_service.dart';
import '../services/tts_service.dart';
import '../theme/highlight_palette.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';
import '../util/continue_listening.dart';
import '../util/document_labels.dart';
import '../util/friendly_errors.dart';
import '../util/tts_sentence_offsets.dart';
import '../widgets/audio_player_sheet.dart';
import '../widgets/document_companion_panel.dart';
import '../widgets/tts_player_sheet.dart';
import 'document_edit_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({
    super.key,
    required this.repository,
    required this.ownerUid,
    required this.documentId,
  });

  final DocumentRepository repository;
  final String ownerUid;
  final String documentId;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final _ai = AiService();
  final _tts = TtsService();
  final ScrollController _scrollController = ScrollController();
  bool _showOriginalText = false;
  bool _fabExpanded = false;
  bool _markedOpenedThisScreen = false;

  Timer? _createHighlightDebounce;
  int _selectableNonce = 0;

  String _spanCacheDocKey = '';
  List<DocumentHighlight>? _spanCacheHl;
  String? _spanCacheText;
  List<InlineSpan>? _spanMem;

  // VO-08: följ-med-i-texten under enhetsröst-uppläsning.
  String? _ttsTrackedText;
  List<({int start, int end})>? _ttsOffsets;
  DateTime? _lastManualScrollAt;
  final List<TapGestureRecognizer> _sentenceTapRecognizers = [];

  @override
  void initState() {
    super.initState();
    _tts.addListener(_onTtsChangedForFollowAlong);
    _scrollController.addListener(_onManualScroll);
  }

  @override
  void dispose() {
    _tts.removeListener(_onTtsChangedForFollowAlong);
    _scrollController.removeListener(_onManualScroll);
    for (final r in _sentenceTapRecognizers) {
      r.dispose();
    }
    _createHighlightDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTtsChangedForFollowAlong() {
    if (!mounted) return;
    if (_ttsTrackedText == null) return;
    setState(() {});
  }

  void _onManualScroll() {
    // ScrollController.animateTo (auto-scroll) also fires this listener;
    // vi kan inte skilja på dem här, så vi använder en kort spärr istället
    // för att helt undvika auto-scroll direkt efter en användarscroll.
    _lastManualScrollAt = DateTime.now();
  }

  String _sourceTypeLabel(UserDocument d) => documentTypeVisual(d.sourceType).label;

  String? _sourceDomain(UserDocument d) {
    final raw = d.sourceUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    final host = uri?.host.trim() ?? '';
    if (host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  Future<void> _openNotesSheet(UserDocument d) async {
    _fabExpanded = false;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: MiraiTokens.bgElevated,
      builder: (ctx) => _NotesBottomSheet(
        doc: d,
        repository: widget.repository,
      ),
    );
  }

  Future<void> _openChatSheet(UserDocument d) async {
    _fabExpanded = false;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: MiraiTokens.bgElevated,
      builder: (ctx) => _ChatBottomSheet(
        doc: d,
        repository: widget.repository,
      ),
    );
  }

  /// Vid överlapp: lägst startOffset vinner; vid samma start, längst intervall.
  DocumentHighlight? _highlightCovering(List<DocumentHighlight> list, int index) {
    DocumentHighlight? best;
    var score = (-1 << 62);
    for (final h in list) {
      if (index < h.startOffset || index >= h.endOffset) continue;
      final span = h.endOffset - h.startOffset;
      final s = -h.startOffset * 1000000 + span;
      if (s > score) {
        score = s;
        best = h;
      }
    }
    return best;
  }

  List<InlineSpan> _buildHighlightSpans(
    String fullText,
    List<DocumentHighlight> highlights,
    TextStyle baseStyle,
  ) {
    if (fullText.isEmpty) {
      return const [TextSpan(text: '')];
    }

    DocumentHighlight? at(int i) => _highlightCovering(highlights, i);

    final spans = <InlineSpan>[];
    var i = 0;
    while (i < fullText.length) {
      final hl = at(i);

      late final int jExclusive;
      if (hl == null) {
        var k = i + 1;
        while (k < fullText.length && at(k) == null) {
          k++;
        }
        jExclusive = k;
      } else {
        var k = i + 1;
        while (k < fullText.length &&
            at(k)?.startOffset == hl.startOffset &&
            at(k)?.endOffset == hl.endOffset &&
            at(k)?.color == hl.color) {
          k++;
        }
        jExclusive = k;
      }

      final slice = fullText.substring(i, jExclusive);
      spans.add(
        TextSpan(
          text: slice,
          style:
              hl == null
                  ? baseStyle
                  : baseStyle.copyWith(
                      backgroundColor: HighlightPalette.resolve(hl.color),
                    ),
        ),
      );
      i = jExclusive;
    }
    return spans;
  }

  /// VO-08: som [_buildHighlightSpans] men lägger även på tap-att-hoppa och
  /// en kant/understrykningsstil för meningen som TTS just nu läser upp.
  List<InlineSpan> _buildFollowAlongSpans(
    String fullText,
    List<DocumentHighlight> highlights,
    TextStyle baseStyle,
    List<({int start, int end})> sentenceOffsets,
    int currentSentenceIndex,
  ) {
    if (fullText.isEmpty) return const [TextSpan(text: '')];

    DocumentHighlight? at(int i) => _highlightCovering(highlights, i);
    int? sentenceAt(int i) {
      for (var s = 0; s < sentenceOffsets.length; s++) {
        final o = sentenceOffsets[s];
        if (i >= o.start && i < o.end) return s;
      }
      return null;
    }

    // Körs under build: synkron dispose här tvingar gesture-arenan att
    // avgöras mitt i build (tap-callback → notifyListeners → "tree locked"/
    // defunct-assertions). Skjut därför upp disposal till efter framen.
    if (_sentenceTapRecognizers.isNotEmpty) {
      final old = List<TapGestureRecognizer>.of(_sentenceTapRecognizers);
      _sentenceTapRecognizers.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in old) {
          r.dispose();
        }
      });
    }

    final spans = <InlineSpan>[];
    var i = 0;
    while (i < fullText.length) {
      final hl = at(i);
      final sentenceIdx = sentenceAt(i);

      var k = i + 1;
      while (k < fullText.length &&
          at(k)?.startOffset == hl?.startOffset &&
          at(k)?.endOffset == hl?.endOffset &&
          at(k)?.color == hl?.color &&
          sentenceAt(k) == sentenceIdx) {
        k++;
      }

      final slice = fullText.substring(i, k);
      var style = hl == null
          ? baseStyle
          : baseStyle.copyWith(backgroundColor: HighlightPalette.resolve(hl.color));
      if (sentenceIdx != null && sentenceIdx == currentSentenceIndex) {
        style = style.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: MiraiTokens.accent,
          decorationThickness: 2,
          fontWeight: FontWeight.w600,
        );
      }

      TapGestureRecognizer? recognizer;
      if (sentenceIdx != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => _tts.playFrom(sentenceIdx);
        _sentenceTapRecognizers.add(recognizer);
      }

      spans.add(TextSpan(text: slice, style: style, recognizer: recognizer));
      i = k;
    }
    return spans;
  }

  List<InlineSpan> _memoSpans(UserDocument doc, String fullText, TextStyle base) {
    const big = 10000;
    if (fullText.length <= big) {
      return _buildHighlightSpans(fullText, doc.highlights, base);
    }

    final upd = doc.updatedAt?.millisecondsSinceEpoch ?? 0;
    final hlKey =
        '${doc.id}|$upd|${fullText.hashCode}|'
        '${doc.highlights.map((e) => '${e.startOffset}-${e.endOffset}-${e.color}-${e.note}').join('|')}';

    if (_spanCacheDocKey != doc.id ||
        _spanCacheText != hlKey ||
        _spanCacheHl?.length != doc.highlights.length) {
      _spanCacheDocKey = doc.id;
      _spanCacheText = hlKey;
      _spanCacheHl = doc.highlights;
      _spanMem = _buildHighlightSpans(fullText, doc.highlights, base);
    }
    return _spanMem ?? _buildHighlightSpans(fullText, doc.highlights, base);
  }

  double _estimatedScrollOffsetToSelectableTop({
    required UserDocument d,
    required TextTheme textTheme,
    required double innerColumnWidth,
  }) {
    double h = MiraiTokens.spaceLg.toDouble();
    final summary = (d.summary ?? '').trim();
    final summaryInnerW = math.max(
      0.0,
      innerColumnWidth - MiraiTokens.spaceMd * 2,
    );

    if (summary.isNotEmpty) {
      final lh = TextPainter(
        text: TextSpan(
          text: 'SAMMANFATTNING',
          style: textTheme.labelSmall?.copyWith(
                color: MiraiTokens.textTertiary,
              ) ??
              const TextStyle(
                height: 1.25,
                color: MiraiTokens.textTertiary,
                fontSize: 11,
              ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      h += lh.height + MiraiTokens.spaceXs;
      final sumStyle =
          textTheme.bodyMedium?.copyWith(height: 1.55) ??
          const TextStyle(height: 1.55);
      final sp = TextPainter(
        text: TextSpan(text: summary, style: sumStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: summaryInnerW);
      h +=
          MiraiTokens.spaceMd * 2 +
          sp.height +
          MiraiTokens.spaceMd +
          MiraiTokens.spaceXs;
    }

    final lh2 = TextPainter(
      text: TextSpan(
        text: 'TEXT',
        style:
            textTheme.labelSmall?.copyWith(color: MiraiTokens.textTertiary) ??
            const TextStyle(
              height: 1.25,
              color: MiraiTokens.textTertiary,
              fontSize: 11,
            ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    h += lh2.height + MiraiTokens.spaceXs;
    // Översta padding i textcontainern (Selectable börjar härifrån).
    h += MiraiTokens.spaceMd;

    return h;
  }

  List<DocumentHighlight> _clipHighlights(
    List<DocumentHighlight> hl,
    int endExclusive,
  ) {
    if (hl.isEmpty || endExclusive <= 0) return const [];
    final out = <DocumentHighlight>[];
    for (final h in hl) {
      if (h.endOffset <= 0 || h.startOffset >= endExclusive) continue;
      final s = math.max(0, h.startOffset);
      final e = math.min(endExclusive, h.endOffset);
      if (s < e) {
        out.add(
          DocumentHighlight(
            startOffset: s,
            endOffset: e,
            color: h.color,
            note: h.note,
          ),
        );
      }
    }
    return out;
  }

  double _heightThroughChar(
    String fullText,
    List<DocumentHighlight> highlights,
    TextStyle baseStyle,
    int charExclusive,
    double maxWidth,
  ) {
    final end = charExclusive.clamp(0, fullText.length);
    if (end <= 0) return 0;
    final sub = fullText.substring(0, end);
    final clipped = _clipHighlights(highlights, end);
    final spans = _buildHighlightSpans(sub, clipped, baseStyle);
    try {
      final tp = TextPainter(
        text: TextSpan(children: spans),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      return tp.height;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _persistHighlights(UserDocument doc, List<DocumentHighlight> list) async {
    await widget.repository.update(doc.copyWith(highlights: List.from(list)));
    _invalidateSpanMem();
  }

  void _invalidateSpanMem() {
    _spanMem = null;
    _spanCacheText = null;
    _spanCacheHl = null;
    _spanCacheDocKey = '';
  }

  TextSelection _normalizeSelection(TextSelection s) {
    final lo = math.min(s.baseOffset, s.extentOffset);
    final hi = math.max(s.baseOffset, s.extentOffset);
    return TextSelection(baseOffset: lo, extentOffset: hi);
  }

  void _scheduleCreateOffer(UserDocument doc, TextSelection sel, String fullText) {
    _createHighlightDebounce?.cancel();

    final norm = _normalizeSelection(sel);
    if (norm.baseOffset == norm.extentOffset) return;

    final maxLen = fullText.length;
    if (maxLen == 0) return;

    final aIn = math.max(0, math.min(norm.baseOffset, maxLen));
    final bIn = math.max(0, math.min(norm.extentOffset, maxLen));
    final lo = math.min(aIn, bIn);
    final hi = math.max(aIn, bIn);
    if (lo >= hi) return;

    for (final idx in [lo, hi - 1]) {
      if (idx >= 0 &&
          idx < maxLen &&
          _highlightCovering(doc.highlights, idx) != null) {
        return;
      }
    }

    _createHighlightDebounce = Timer(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      _showCreateHighlightSheet(doc: doc, start: lo, end: hi, fullText: fullText);
    });
  }

  int? _lastAutoScrolledSentence;

  /// VO-08: varsam auto-scroll till aktuell mening — hoppas över om
  /// användaren scrollat manuellt de senaste 3 sekunderna, och bara en
  /// gång per meningsbyte (inte på varje rebuild).
  void _scrollToCurrentSentence({
    required String fullText,
    required List<DocumentHighlight> highlights,
    required TextStyle baseStyle,
    required double maxWidthText,
    required double precedingToTextPx,
  }) {
    final idx = _tts.currentSentenceIndex;
    if (idx < 0 || idx == _lastAutoScrolledSentence) return;
    final offsets = _ttsOffsets;
    if (offsets == null || idx >= offsets.length) return;
    final lastManual = _lastManualScrollAt;
    if (lastManual != null &&
        DateTime.now().difference(lastManual) < const Duration(seconds: 3)) {
      return;
    }
    _lastAutoScrolledSentence = idx;
    _scrollToApproximateChar(
      fullText,
      highlights,
      baseStyle,
      maxWidthText,
      offsets[idx].start,
      MediaQuery.sizeOf(context).height,
      precedingToTextPx,
    );
  }

  void _scrollToApproximateChar(
    String fullText,
    List<DocumentHighlight> highlights,
    TextStyle baseStyle,
    double maxWidthText,
    int charOffset,
    double viewportHeight,
    double precedingHeight,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || fullText.isEmpty) return;

      final y =
          precedingHeight +
          _heightThroughChar(
            fullText,
            highlights,
            baseStyle,
            charOffset.clamp(0, fullText.length),
            maxWidthText,
          );

      final target = math.max(0.0, y - viewportHeight * 0.33);
      _scrollController.animateTo(
        math.min(target, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _showCreateHighlightSheet({
    required UserDocument doc,
    required int start,
    required int end,
    required String fullText,
  }) {
    final preview = () {
      if (fullText.isEmpty || start >= end) return '';
      final max = math.min(end, fullText.length);
      final s = math.max(0, start);
      return fullText.substring(s, max);
    }();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: MiraiTokens.bgElevated,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(ctx).bottom + MiraiTokens.spaceLg,
            left: MiraiTokens.spaceLg,
            right: MiraiTokens.spaceLg,
            top: MiraiTokens.spaceSm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ny markering', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: MiraiTokens.spaceXs),
              Text(
                preview.length <= 240 ? preview : '${preview.substring(0, 240)}…',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: MiraiTokens.textTertiary,
                    ),
              ),
              const SizedBox(height: MiraiTokens.spaceMd),
              Text('Highlighta · välj färg', style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: MiraiTokens.spaceSm),
              Wrap(
                spacing: MiraiTokens.spaceSm,
                runSpacing: MiraiTokens.spaceSm,
                children: [
                  for (final id in HighlightPalette.ids)
                    Material(
                      elevation: 1,
                      color: HighlightPalette.resolve(id),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                      ),
                      child: InkWell(
                        onTap: () async {
                          Navigator.pop(ctx);
                          final next = DocumentHighlight(
                            startOffset: start,
                            endOffset: end,
                            color: id,
                          );
                          await _persistHighlights(doc, [...doc.highlights, next]);
                          if (!mounted) return;
                          setState(() => _selectableNonce++);
                        },
                        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                        child: const SizedBox(width: 52, height: 44),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: MiraiTokens.spaceLg),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditHighlightSheet(UserDocument doc, int highlightIndex) async {
    if (highlightIndex < 0 || highlightIndex >= doc.highlights.length) return;
    final hl = doc.highlights[highlightIndex];
    final fullText = doc.extractedText ?? '';

    final selectedText =
        hl.startOffset >= 0 &&
                hl.endOffset <= fullText.length &&
                hl.startOffset < hl.endOffset
            ? fullText.substring(hl.startOffset, hl.endOffset)
            : '';

    final noteCtrl = TextEditingController(text: hl.note ?? '');
    var currentHl = hl;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: MiraiTokens.bgElevated,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + MiraiTokens.spaceLg,
                left: MiraiTokens.spaceLg,
                right: MiraiTokens.spaceLg,
                top: MiraiTokens.spaceSm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Markering',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  Container(
                    padding: const EdgeInsets.all(MiraiTokens.spaceMd),
                    decoration: BoxDecoration(
                      color: MiraiTokens.bgRaised,
                      borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                      border: Border.all(color: MiraiTokens.borderSubtle),
                    ),
                    child: Text(
                      selectedText.trim().isEmpty ? '(inget utdrag)' : selectedText,
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
                  const SizedBox(height: MiraiTokens.spaceMd),
                  Text('Färg', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: MiraiTokens.spaceSm),
                  Wrap(
                    spacing: MiraiTokens.spaceXs,
                    runSpacing: MiraiTokens.spaceXs,
                    children: [
                      for (final id in HighlightPalette.ids)
                        FilterChip(
                          avatar: SizedBox.square(
                            dimension: 22,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: HighlightPalette.resolve(id),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          label: Text(id, style: const TextStyle(fontSize: 13)),
                          showCheckmark: false,
                          selected: currentHl.color.toLowerCase() == id.toLowerCase(),
                          onSelected: (v) {
                            if (!v) return;
                            setSheet(() {
                              currentHl = DocumentHighlight(
                                startOffset: currentHl.startOffset,
                                endOffset: currentHl.endOffset,
                                color: id,
                                note: currentHl.note,
                              );
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: MiraiTokens.spaceMd),
                  TextField(
                    controller: noteCtrl,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Anteckning (valfritt)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: MiraiTokens.spaceMd),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final list = List<DocumentHighlight>.from(doc.highlights)
                            ..removeAt(highlightIndex);
                          await _persistHighlights(doc, list);
                          if (!mounted) return;
                          setState(() => _selectableNonce++);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, color: MiraiTokens.danger),
                        label: const Text(
                          'Ta bort markering',
                          style: TextStyle(color: MiraiTokens.danger),
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final list = List<DocumentHighlight>.from(doc.highlights);
                          list[highlightIndex] = DocumentHighlight(
                            startOffset: hl.startOffset,
                            endOffset: hl.endOffset,
                            color: currentHl.color,
                            note: noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          );
                          await _persistHighlights(doc, list);
                          if (!mounted) return;
                          setState(() => _selectableNonce++);
                        },
                        child: const Text('Spara'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(noteCtrl.dispose);
  }

  void _showHighlightsListSheet({
    required UserDocument doc,
    required String fullText,
    required TextStyle baseStyle,
    required double maxWidthText,
    required double precedingToTextPx,
  }) {
    final mq = MediaQuery.of(context);

    final sorted = [...doc.highlights]
      ..sort((a, b) => a.startOffset.compareTo(b.startOffset));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MiraiTokens.bgElevated,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SizedBox(
          height: mq.size.height * 0.55,
          child: ListView.builder(
            padding: const EdgeInsets.only(
              bottom: MiraiTokens.spaceLg,
              left: MiraiTokens.spaceMd,
              right: MiraiTokens.spaceMd,
              top: MiraiTokens.spaceSm,
            ),
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final h = sorted[i];
              final idx = doc.highlights.indexWhere(
                (e) =>
                    e.startOffset == h.startOffset &&
                    e.endOffset == h.endOffset &&
                    e.color == h.color &&
                    e.note == h.note,
              );

              final snippet = () {
                if (fullText.isEmpty ||
                    h.startOffset < 0 ||
                    h.startOffset >= fullText.length ||
                    h.startOffset >= h.endOffset) {
                  return '(inget utdrag)';
                }
                final end = math.min(h.endOffset, fullText.length);
                final s =
                    fullText.substring(h.startOffset, end).replaceAll('\n', ' ');
                return s.length > 80 ? '${s.substring(0, 80)}…' : s;
              }();

              return ListTile(
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor: HighlightPalette.resolve(h.color),
                ),
                title: Text(snippet),
                subtitle: (h.note != null && h.note!.trim().isNotEmpty)
                    ? Text(h.note!)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (idx >= 0 && fullText.isNotEmpty) {
                    _scrollToApproximateChar(
                      fullText,
                      doc.highlights,
                      baseStyle,
                      maxWidthText,
                      h.startOffset,
                      mq.size.height,
                      precedingToTextPx,
                    );
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  int _highlightListIndex(DocumentHighlight hit, List<DocumentHighlight> list) {
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e.startOffset == hit.startOffset &&
          e.endOffset == hit.endOffset &&
          e.color == hit.color &&
          e.note == hit.note) {
        return i;
      }
    }
    return -1;
  }

  void _onSelectionChanged(
    UserDocument doc,
    TextSelection sel,
    SelectionChangedCause? cause,
    String fullText,
  ) {
    if (fullText.isEmpty) return;

    if (sel.isCollapsed) {
      _createHighlightDebounce?.cancel();
      if (cause != SelectionChangedCause.tap &&
          cause != SelectionChangedCause.longPress &&
          cause != SelectionChangedCause.doubleTap) {
        return;
      }

      final maxIx = math.max(0, fullText.length - 1);
      final i =
          math.min(math.max(sel.baseOffset, 0), maxIx);
      final hit = _highlightCovering(doc.highlights, i);
      if (hit != null) {
        final idx = _highlightListIndex(hit, doc.highlights);
        if (idx >= 0) {
          unawaited(_showEditHighlightSheet(doc, idx));
        }
      }
      return;
    }

    _scheduleCreateOffer(doc, sel, fullText);
  }

  Future<void> _openEdit(UserDocument d) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditScreen(
          repository: widget.repository,
          initial: d,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(UserDocument d) async {
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Radera dokumentet permanent?'),
        content: const Text(
          'Dokumentet försvinner från biblioteket. Eventuell uppladdad bilaga tas '
          'också bort från molnlagring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Avbryt'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Radera',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    try {
      await widget.repository.delete(d.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att radera. Testa igen om en stund.',
        error: e,
      );
    }
  }

  String _highlightSnippet(String fullText, DocumentHighlight h) {
    if (fullText.isEmpty ||
        h.startOffset < 0 ||
        h.startOffset >= fullText.length ||
        h.startOffset >= h.endOffset) {
      return '(inget utdrag)';
    }
    final end = math.min(h.endOffset, fullText.length);
    final s = fullText.substring(h.startOffset, end).replaceAll('\n', ' ').trim();
    if (s.isEmpty) return '(inget utdrag)';
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  void _playWithDeviceVoice(UserDocument d, String fullText) {
    final text = (d.summary ?? '').trim().isNotEmpty
        ? d.summary!.trim()
        : fullText.trim();
    if (text.isEmpty) return;
    // VO-08: följ-med-i-texten kräver att TTS läser exakt originaltexten
    // (annars stämmer inte teckenoffseten mot vad som visas).
    _ttsTrackedText = text == fullText.trim() ? text : null;
    _ttsOffsets = _ttsTrackedText == null ? null : computeSentenceOffsets(fullText);
    showTtsPlayer(
      context,
      text: text,
      title: d.title,
      subject: null,
      persistListenedSession: kUseFirestoreHomework
          ? (secs) => FirestoreListeningStatsRepository()
              .addListenedSeconds(widget.ownerUid, secs)
          : null,
      onProgressChanged: (progress) {
        widget.repository.update(
          d.copyWith(readingProgress: progress, lastReadAt: DateTime.now()),
        );
        if (mounted) setState(() => _ttsTrackedText = null);
      },
    );
  }

  void _playOriginalRecording(UserDocument d) {
    final url = d.attachmentStorageUrl?.trim();
    if (url == null || url.isEmpty) return;
    showAudioPlayerSheet(
      context,
      title: d.title,
      docId: '${d.id}-original',
      load: () async => DocumentAudioResult(audioUrl: url, truncated: false),
    );
  }

  void _openCloudPlayer(UserDocument d) {
    showAudioPlayerSheet(
      context,
      title: d.title,
      docId: d.id,
      load: () => _ai.documentAudio(documentId: d.id),
      initialProgress: d.readingProgress,
      onPositionChanged: (position, duration, completed) {
        final progress = completed ? 1.0 : computeReadingProgress(position: position, duration: duration);
        widget.repository.update(
          d.copyWith(readingProgress: progress, lastReadAt: DateTime.now()),
        );
      },
    );
  }

  Widget _buildExpandableFab(UserDocument d) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabExpanded) ...[
          _MiniFabAction(
            icon: Icons.sticky_note_2_outlined,
            label: 'Anteckna',
            onTap: () => _openNotesSheet(d),
          ),
          const SizedBox(height: MiraiTokens.spaceSm),
          _MiniFabAction(
            icon: Icons.chat_outlined,
            label: 'Chatta',
            onTap: () => _openChatSheet(d),
          ),
          const SizedBox(height: MiraiTokens.spaceSm),
        ],
        FloatingActionButton(
          heroTag: 'doc-fab-main',
          backgroundColor: MiraiTokens.accent,
          shape: const StadiumBorder(),
          onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
          child: Icon(
            _fabExpanded ? Icons.close_rounded : Icons.edit_note_rounded,
            color: MiraiTokens.textInverse,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return StreamBuilder<UserDocument?>(
      stream: widget.repository.watchOne(widget.documentId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            snap.data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final docSnap = snap.data;
        if (docSnap == null) {
          return const Scaffold(
            body: Center(child: Text('Dokumentet finns inte.')),
          );
        }

        final d = docSnap;
        final fullText = d.extractedText ?? '';
        final hasText = fullText.trim().isNotEmpty;

        if (!_markedOpenedThisScreen) {
          _markedOpenedThisScreen = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.repository.update(d.copyWith(lastReadAt: DateTime.now()));
          });
        }

        final bodyStyle =
            (tt.bodyMedium ?? const TextStyle()).copyWith(
              height: 1.55,
              color: MiraiTokens.textPrimary,
            );

        return LayoutBuilder(
          builder: (context, constraints) {
            final columnOuter =
                math.min(constraints.maxWidth, 480.0).toDouble();
            final innerColumn =
                math.max(
                  0.0,
                  columnOuter - MiraiTokens.spaceLg * 2,
                ).toDouble();
            final textMax =
                math.max(
                  0.0,
                  innerColumn - MiraiTokens.spaceMd * 2,
                ).toDouble();

            Future<void> openBookmarks(double precedingPx) async {
              if (fullText.isEmpty || d.highlights.isEmpty) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Inga markeringar ännu.')),
                );
                return;
              }
              _showHighlightsListSheet(
                doc: d,
                fullText: fullText,
                baseStyle: bodyStyle,
                maxWidthText: textMax,
                precedingToTextPx: precedingPx,
              );
            }

            final precedingToTextPx =
                _estimatedScrollOffsetToSelectableTop(
                  d: d,
                  textTheme: tt,
                  innerColumnWidth: innerColumn,
                );

            Widget buildTextSection() {
              if (!hasText) {
                return Container(
                  padding: const EdgeInsets.all(MiraiTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: MiraiTokens.bgRaised,
                    borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                    border: Border.all(color: MiraiTokens.borderSubtle),
                  ),
                  child: Text(
                    'Ingen text ännu.',
                    style: bodyStyle,
                  ),
                );
              }

              final followAlongActive =
                  _ttsTrackedText != null && _tts.state != TtsPlayerState.idle;
              final spans = followAlongActive
                  ? _buildFollowAlongSpans(
                      fullText,
                      d.highlights,
                      bodyStyle,
                      _ttsOffsets ?? const [],
                      _tts.currentSentenceIndex,
                    )
                  : _memoSpans(d, fullText, bodyStyle);
              final keySuffix =
                  '${d.updatedAt?.millisecondsSinceEpoch ?? 0}_${d.highlights.length}_$_selectableNonce';

              if (followAlongActive) {
                _scrollToCurrentSentence(
                  fullText: fullText,
                  highlights: d.highlights,
                  baseStyle: bodyStyle,
                  maxWidthText: textMax,
                  precedingToTextPx: precedingToTextPx,
                );
              }

              return Container(
                padding: const EdgeInsets.all(MiraiTokens.spaceMd),
                decoration: BoxDecoration(
                  color: MiraiTokens.bgRaised,
                  borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                  border: Border.all(color: MiraiTokens.borderSubtle),
                ),
                child: SelectableText.rich(
                  key: ValueKey('doc_$keySuffix'),
                  TextSpan(children: spans),
                  onSelectionChanged: (sel, cause) =>
                      _onSelectionChanged(d, sel, cause, fullText),
                ),
              );
            }

            final listenEnabled =
                (d.summary ?? d.extractedText ?? '').trim().isNotEmpty;

            return Scaffold(
              appBar: AppBar(
                title: Text(d.title),
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'Mer',
                    onSelected: (value) async {
                      if (!context.mounted) return;
                      if (value == 'edit') await _openEdit(d);
                      if (value == 'delete') await _confirmDelete(d);
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.edit_rounded),
                          title: Text('Redigera'),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: MiraiTokens.danger,
                          ),
                          title: Text(
                            'Radera',
                            style: TextStyle(color: MiraiTokens.danger),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_showOriginalText)
                    IconButton(
                      tooltip: 'Visa markeringar (${d.highlights.length})',
                      icon: Badge.count(
                        count: d.highlights.length,
                        isLabelVisible: d.highlights.isNotEmpty,
                        child: Icon(
                          d.highlights.isEmpty
                              ? Icons.bookmark_outline_rounded
                              : Icons.bookmarks_outlined,
                        ),
                      ),
                      onPressed: () => openBookmarks(precedingToTextPx),
                    ),
                ],
              ),
              body: SafeArea(
                child: Center(
                  child: MiraiAdaptiveBox(
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(MiraiTokens.spaceLg),
                      children: [
                        Wrap(
                          spacing: MiraiTokens.spaceXs,
                          runSpacing: MiraiTokens.spaceXs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: MiraiTokens.bgRaised,
                                borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
                                border: Border.all(color: MiraiTokens.borderSubtle),
                              ),
                              child: Text(
                                _sourceTypeLabel(d),
                                style: tt.labelSmall?.copyWith(color: MiraiTokens.textSecondary),
                              ),
                            ),
                            if (_sourceDomain(d) != null)
                              Text(
                                'från ${_sourceDomain(d)!}',
                                style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                              ),
                            if (d.readingProgress > 0)
                              Text(
                                'Läst ${((d.readingProgress.clamp(0.0, 1.0)) * 100).round()}%',
                                style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                              ),
                          ],
                        ),
                        const SizedBox(height: MiraiTokens.spaceLg),
                        if (d.sourceType == 'recording' && d.attachment != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _playOriginalRecording(d),
                              icon: const Icon(Icons.mic_none_rounded),
                              label: const Text('Spela upp originalljudet'),
                            ),
                          ),
                          const SizedBox(height: MiraiTokens.spaceMd),
                        ],
                        Text(
                          'SAMMANFATTNING',
                          style: tt.labelSmall?.copyWith(
                            color: MiraiTokens.textTertiary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: MiraiTokens.spaceXs),
                        Container(
                          padding: const EdgeInsets.all(MiraiTokens.spaceMd),
                          decoration: BoxDecoration(
                            color: MiraiTokens.bgRaised,
                            borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                            border: Border.all(color: MiraiTokens.borderSubtle),
                          ),
                          child: Text(
                            (d.summary ?? '').trim().isEmpty
                                ? 'Ingen sammanfattning ännu.'
                                : d.summary!.trim(),
                            style: tt.bodyLarge?.copyWith(
                              height: 1.6,
                              color: (d.summary ?? '').trim().isEmpty
                                  ? MiraiTokens.textTertiary
                                  : MiraiTokens.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: MiraiTokens.spaceMd),
                        FilledButton.icon(
                          onPressed: !listenEnabled
                              ? null
                              : () {
                                  if (kUseFirestoreHomework) {
                                    _openCloudPlayer(d);
                                  } else {
                                    _playWithDeviceVoice(d, fullText);
                                  }
                                },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Lyssna'),
                        ),
                        const SizedBox(height: MiraiTokens.spaceXs),
                        Center(
                          child: TextButton(
                            onPressed: !listenEnabled
                                ? null
                                : () => _playWithDeviceVoice(d, fullText),
                            child: const Text('Lyssna med enhetsröst'),
                          ),
                        ),
                        if (!kUseFirestoreHomework) ...[
                          const SizedBox(height: MiraiTokens.spaceXs),
                          Text(
                            'Molnuppläsning kräver Firestore-läge. I demo-läget används enhetsrösten.',
                            style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                          ),
                        ],
                        const SizedBox(height: MiraiTokens.spaceSm),
                        OutlinedButton(
                          onPressed: hasText
                              ? () => setState(() => _showOriginalText = !_showOriginalText)
                              : null,
                          child: Text(_showOriginalText ? 'Dölj originaltext' : 'Visa originaltext'),
                        ),
                        const SizedBox(height: MiraiTokens.spaceSm),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          child: _showOriginalText
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ORIGINALTEXT',
                                      style: tt.labelSmall?.copyWith(
                                        color: MiraiTokens.textTertiary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: MiraiTokens.spaceXs),
                                    buildTextSection(),
                                    if (d.highlights.isNotEmpty) ...[
                                      const SizedBox(height: MiraiTokens.spaceMd),
                                      Text(
                                        'MARKERINGAR',
                                        style: tt.labelSmall?.copyWith(
                                          color: MiraiTokens.textTertiary,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: MiraiTokens.spaceXs),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: MiraiTokens.bgRaised,
                                          borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                                          border: Border.all(color: MiraiTokens.borderSubtle),
                                        ),
                                        child: Column(
                                          children: [
                                            for (var i = 0; i < d.highlights.length && i < 6; i++)
                                              ListTile(
                                                dense: true,
                                                leading: CircleAvatar(
                                                  radius: 7,
                                                  backgroundColor: HighlightPalette.resolve(
                                                    d.highlights[i].color,
                                                  ),
                                                ),
                                                title: Text(
                                                  _highlightSnippet(fullText, d.highlights[i]),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                onTap: () => _showEditHighlightSheet(d, i),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: MiraiTokens.space2xl),
                      ],
                    ),
                  ),
                ),
              ),
              floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
              floatingActionButton: _buildExpandableFab(d),
            );
          },
        );
      },
    );
  }
}

class _MiniFabAction extends StatelessWidget {
  const _MiniFabAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: MiraiTokens.bgRaised,
            borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
            border: Border.all(color: MiraiTokens.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: MiraiTokens.textSecondary),
              const SizedBox(width: MiraiTokens.spaceXs),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesBottomSheet extends StatefulWidget {
  const _NotesBottomSheet({
    required this.doc,
    required this.repository,
  });

  final UserDocument doc;
  final DocumentRepository repository;

  @override
  State<_NotesBottomSheet> createState() => _NotesBottomSheetState();
}

class _NotesBottomSheetState extends State<_NotesBottomSheet> {
  late final TextEditingController _inputCtrl = TextEditingController();
  bool _saving = false;

  List<String> _entries(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return const [];
    final out = t
        .split(RegExp(r'\n{2,}'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return out.reversed.toList();
  }

  Future<void> _addNote() async {
    final msg = _inputCtrl.text.trim();
    if (msg.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final prev = (widget.doc.userNotes ?? '').trim();
      final next = prev.isEmpty ? msg : '$prev\n\n$msg';
      await widget.repository.update(widget.doc.copyWith(userNotes: next));
      if (!mounted) return;
      _inputCtrl.clear();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        'Hoppsan – det gick inte att spara anteckningen. Testa igen om en stund.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _entries(widget.doc.userNotes);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: MiraiTokens.spaceLg,
          right: MiraiTokens.spaceLg,
          top: MiraiTokens.spaceSm,
          bottom: MediaQuery.viewInsetsOf(context).bottom + MiraiTokens.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Anteckningar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: MiraiTokens.spaceSm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: notes.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(MiraiTokens.spaceMd),
                      decoration: BoxDecoration(
                        color: MiraiTokens.bgRaised,
                        borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                        border: Border.all(color: MiraiTokens.borderSubtle),
                      ),
                      child: Text(
                        'Inga anteckningar ännu.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: MiraiTokens.textTertiary,
                            ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: notes.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) => Container(
                        padding: const EdgeInsets.all(MiraiTokens.spaceSm),
                        decoration: BoxDecoration(
                          color: MiraiTokens.bgRaised,
                          borderRadius: BorderRadius.circular(MiraiTokens.radiusMd),
                          border: Border.all(color: MiraiTokens.borderSubtle),
                        ),
                        child: Text(notes[i]),
                      ),
                    ),
            ),
            const SizedBox(height: MiraiTokens.spaceSm),
            TextField(
              controller: _inputCtrl,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Ny anteckning…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: MiraiTokens.spaceSm),
            FilledButton.icon(
              onPressed: _saving ? null : _addNote,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Skicka'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBottomSheet extends StatelessWidget {
  const _ChatBottomSheet({
    required this.doc,
    required this.repository,
  });

  final UserDocument doc;
  final DocumentRepository repository;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: MiraiTokens.spaceLg,
          right: MiraiTokens.spaceLg,
          top: MiraiTokens.spaceSm,
          bottom: MediaQuery.viewInsetsOf(context).bottom + MiraiTokens.spaceLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Chatt om dokumentet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: MiraiTokens.spaceSm),
            if (kUseFirestoreHomework)
              SizedBox(
                height: h.clamp(360.0, 640.0),
                child: DocumentChatSection(
                  doc: doc,
                  repository: repository,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: MiraiTokens.spaceLg),
                child: Text(
                  'Chatt om dokumentet kräver molnläge (Firestore). '
                  'I demo-läget är chatten avstängd.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: MiraiTokens.textTertiary,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
