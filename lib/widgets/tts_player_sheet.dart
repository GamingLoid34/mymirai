import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/homework_item.dart';
import '../services/tts_service.dart';
import '../theme/breakpoints.dart';
import '../theme/mirai_tokens.dart';

void showTtsPlayer(
  BuildContext context, {
  required String text,
  required String title,
  required String? subject,
  Future<void> Function(int listenedSeconds)? persistListenedSession,
  VoidCallback? onFinished,
  void Function(double progress)? onProgressChanged,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => TtsPlayerSheet(
      title: title,
      subject: subject,
      text: text,
      persistListenedSession: persistListenedSession,
      onFinished: onFinished,
      onProgressChanged: onProgressChanged,
    ),
  );
}

Future<void> showTtsPlayerSheet({
  required BuildContext context,
  required HomeworkItem item,
  required String title,
  required String subject,
  required String text,
}) async {
  showTtsPlayer(
    context,
    text: text,
    title: title,
    subject: subject,
  );
}

class TtsPlayerSheet extends StatefulWidget {
  const TtsPlayerSheet({
    super.key,
    required this.title,
    required this.subject,
    required this.text,
    this.persistListenedSession,
    this.onFinished,
    this.onProgressChanged,
  });

  final String title;
  final String? subject;
  final String text;

  /// Chunk I: vuxendokument-flödet rapporterar ack. sekunder aktiv uppläsning.
  final Future<void> Function(int listenedSeconds)? persistListenedSession;

  /// AO-06: kallas när uppspelningen når slutet naturligt.
  final VoidCallback? onFinished;

  /// VO-02: kallas med (currentSentenceIndex+1)/sentences.length vid stängning.
  final void Function(double progress)? onProgressChanged;

  @override
  State<TtsPlayerSheet> createState() => _TtsPlayerSheetState();
}

class _TtsPlayerSheetState extends State<TtsPlayerSheet> {
  final TtsService _tts = TtsService();
  final ScrollController _scroll = ScrollController();
  static const _rates = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _tts.setListeningReporter(widget.persistListenedSession);
    _tts.onFinished = widget.onFinished;
    _tts.addListener(_onTtsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tts.loadAndPlay(widget.text);
    });
  }

  @override
  void dispose() {
    final total = _tts.sentences.length;
    final onProgress = widget.onProgressChanged;
    if (total > 0 && onProgress != null) {
      final doneCount = _tts.currentSentenceIndex < 0
          ? total
          : _tts.currentSentenceIndex + 1;
      final progress = doneCount / total;
      // dispose körs medan trädet finaliseras (låst) — anropa callbacken
      // först efter framen så att föräldern kan köra setState säkert.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onProgress(progress);
      });
    }
    _tts.removeListener(_onTtsChanged);
    _tts.onFinished = null;
    _tts.stop().then((_) {
      _tts.setListeningReporter(null);
    });
    _scroll.dispose();
    super.dispose();
  }

  void _onTtsChanged() {
    if (!mounted) return;
    setState(() {});
    if (_tts.shouldShowSwedishWarning) {
      _tts.markSwedishWarningShown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Svensk röst saknas. Spelar engelska istället. Prova mobilappen för svenska röster.',
          ),
        ),
      );
    }
    if (_tts.currentSentenceIndex >= 0 && _scroll.hasClients) {
      final target = (_tts.currentSentenceIndex * 60.0)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, sheetScrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: MiraiTokens.bgElevated,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(MiraiTokens.radiusXl),
            ),
          ),
          child: Center(
            child: MiraiAdaptiveBox(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MiraiTokens.bgInteractive,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MiraiTokens.spaceLg,
                      vertical: MiraiTokens.spaceSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.subject != null && widget.subject!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: MiraiTokens.accentSoft,
                              borderRadius: BorderRadius.circular(
                                MiraiTokens.radiusPill,
                              ),
                            ),
                            child: Text(
                              widget.subject!,
                              style: tt.labelSmall?.copyWith(
                                color: MiraiTokens.textSecondary,
                              ),
                            ),
                          ),
                        const SizedBox(height: MiraiTokens.spaceXs),
                        Text(
                          widget.title,
                          style: tt.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: _tts,
                      builder: (context, value) {
                        return ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                            horizontal: MiraiTokens.spaceLg,
                            vertical: MiraiTokens.spaceMd,
                          ),
                          itemCount: _tts.sentences.length,
                          itemBuilder: (context, idx) {
                            final isCurrent = idx == _tts.currentSentenceIndex;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? MiraiTokens.accentSoft
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  MiraiTokens.radiusSm,
                                ),
                              ),
                              child: Text(
                                _tts.sentences[idx],
                                style: tt.bodyMedium?.copyWith(
                                  color: isCurrent
                                      ? MiraiTokens.textPrimary
                                      : MiraiTokens.textSecondary,
                                  height: 1.6,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (_tts.state == TtsPlayerState.error &&
                      (_tts.errorMessage?.isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: MiraiTokens.spaceLg,
                        vertical: MiraiTokens.spaceXs,
                      ),
                      child: Text(
                        _tts.errorMessage!,
                        style: tt.bodySmall?.copyWith(color: MiraiTokens.warning),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MiraiTokens.spaceLg,
                      MiraiTokens.spaceMd,
                      MiraiTokens.spaceLg,
                      MiraiTokens.spaceLg,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'Föregående mening',
                          icon: const Icon(
                            Icons.replay_10_rounded,
                            size: 32,
                            color: MiraiTokens.textSecondary,
                          ),
                          onPressed: _tts.sentences.isEmpty
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  _tts.skipBackward();
                                },
                        ),
                        ListenableBuilder(
                          listenable: _tts,
                          builder: (context, value) {
                            final playing =
                                _tts.state == TtsPlayerState.playing;
                            return Material(
                              color: MiraiTokens.accent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  if (playing) {
                                    _tts.pause();
                                  } else if (_tts.state ==
                                      TtsPlayerState.paused) {
                                    _tts.resume();
                                  } else {
                                    _tts.loadAndPlay(widget.text);
                                  }
                                },
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: Icon(
                                    playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 32,
                                    color: MiraiTokens.textInverse,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Nästa mening',
                          icon: const Icon(
                            Icons.forward_10_rounded,
                            size: 32,
                            color: MiraiTokens.textSecondary,
                          ),
                          onPressed: _tts.sentences.isEmpty
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  _tts.skipForward();
                                },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: MiraiTokens.spaceLg),
                    child: ListenableBuilder(
                      listenable: _tts,
                      builder: (context, value) {
                        return GestureDetector(
                          onTap: () {
                            final cur = _rates.indexOf(_tts.speechRate);
                            final next = _rates[(cur + 1) % _rates.length];
                            _tts.setSpeechRate(next);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: MiraiTokens.bgRaised,
                              border: const Border.fromBorderSide(
                                BorderSide(
                                  color: MiraiTokens.borderSubtle,
                                  width: 0.5,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(
                                MiraiTokens.radiusPill,
                              ),
                            ),
                            child: Text(
                              '${_tts.speechRate.toStringAsFixed(_tts.speechRate == _tts.speechRate.roundToDouble() ? 0 : 2)}×',
                              style: tt.labelMedium?.copyWith(
                                color: MiraiTokens.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
