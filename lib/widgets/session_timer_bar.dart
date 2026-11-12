import 'package:flutter/material.dart';

import '../theme/mirai_tokens.dart';

/// Tunn bar som lugnt krymper under sessionens tidslängd. Ingen ticking,
/// inga siffror — bara en visuell känsla av tid som går.
class SessionTimerBar extends StatefulWidget {
  const SessionTimerBar({
    super.key,
    required this.duration,
    required this.onTimeUp,
  });

  final Duration duration;
  final VoidCallback onTimeUp;

  @override
  State<SessionTimerBar> createState() => _SessionTimerBarState();
}

class _SessionTimerBarState extends State<SessionTimerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onTimeUp();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final remaining = 1 - _controller.value;
        final isLastMinute = widget.duration.inSeconds > 0 &&
            widget.duration * remaining <= const Duration(minutes: 1);
        return SizedBox(
          height: 4,
          child: LinearProgressIndicator(
            value: remaining,
            minHeight: 4,
            backgroundColor: MiraiTokens.bgInteractive,
            color: isLastMinute ? MiraiTokens.warning : MiraiTokens.accent,
          ),
        );
      },
    );
  }
}
