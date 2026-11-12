import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/ai_service.dart';
import '../theme/mirai_tokens.dart';

Future<void> showPremiumListeningSheet(
  BuildContext context, {
  required Future<PremiumListeningStoryResult> Function() load,
  String? titleHint,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _PremiumListeningSheetBody(
      load: load,
      titleHint: titleHint,
    ),
  );
}

class _PremiumListeningSheetBody extends StatefulWidget {
  const _PremiumListeningSheetBody({
    required this.load,
    this.titleHint,
  });

  final Future<PremiumListeningStoryResult> Function() load;
  final String? titleHint;

  @override
  State<_PremiumListeningSheetBody> createState() =>
      _PremiumListeningSheetBodyState();
}

class _PremiumListeningSheetBodyState extends State<_PremiumListeningSheetBody> {
  final AudioPlayer _player = AudioPlayer();
  PremiumListeningStoryResult? _data;
  Object? _error;
  bool _loading = true;
  bool _showText = false;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((_) {
      if (mounted) setState(() {});
    });
    _player.durationStream.listen((_) {
      if (mounted) setState(() {});
    });
    _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _kick();
  }

  Future<void> _kick() async {
    try {
      final data = await widget.load();
      if (!mounted) return;
      _data = data;
      _loading = false;
      setState(() {});
      await _player.setUrl(data.audioUrl);
      await _player.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _togglePlay() async {
    if (_player.playerState.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.32,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: MiraiTokens.bgRaised,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MiraiTokens.radiusLg),
            ),
            border: Border.all(color: MiraiTokens.borderSubtle),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              MiraiTokens.spaceLg,
              MiraiTokens.spaceMd,
              MiraiTokens.spaceLg,
              MiraiTokens.spaceLg + bottom,
            ),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MiraiTokens.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: MiraiTokens.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _data?.title ?? widget.titleHint ?? 'Molnsaga',
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Stäng',
                  ),
                ],
              ),
              const SizedBox(height: MiraiTokens.spaceSm),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(MiraiTokens.spaceXl),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: MiraiTokens.spaceMd),
                        Text('Skapar saga och ljud …'),
                      ],
                    ),
                  ),
                )
              else if (_error != null)
                Text(
                  'Kunde inte spela molnsagan: $_error',
                  style: tt.bodyMedium?.copyWith(color: MiraiTokens.danger),
                )
              else if (_data != null) ...[
                Builder(
                  builder: (_) {
                    final pos = _player.position;
                    final total = _player.duration ?? Duration.zero;
                    final maxMs = total.inMilliseconds;
                    if (maxMs <= 0) {
                      return const LinearProgressIndicator();
                    }
                    final v = pos.inMilliseconds / maxMs.toDouble();
                    return Slider(
                      value: v.clamp(0.0, 1.0),
                      onChanged: (x) async {
                        final ms = (x * maxMs).round();
                        await _player.seek(Duration(milliseconds: ms));
                      },
                    );
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _togglePlay,
                      icon: Icon(
                        _player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      ),
                      label: Text(_player.playing ? 'Pausa' : 'Spela'),
                    ),
                    const SizedBox(width: MiraiTokens.spaceMd),
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _showText = !_showText),
                      child: Text(_showText ? 'Dölj text' : 'Visa saga-text'),
                    ),
                  ],
                ),
                if (_showText) ...[
                  const SizedBox(height: MiraiTokens.spaceMd),
                  SelectableText(
                    _data!.storyText,
                    style: tt.bodyMedium?.copyWith(height: 1.55),
                  ),
                ],
                const SizedBox(height: MiraiTokens.spaceXs),
                Text(
                  'Ljudlänken går ut efter cirka 90 minuter. Spela om vid behov.',
                  style: tt.bodySmall?.copyWith(color: MiraiTokens.textTertiary),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
