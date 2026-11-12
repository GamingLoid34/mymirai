import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/mirai_tokens.dart';

enum CelebrationSize { medium, large }

/// Kort, generöst firande: konfetti från toppen + haptik.
///
/// Lägger en kortlivad overlay ovanpå aktuell skärm. Anropande skärm
/// behöver inte hålla på någon state.
class Celebration {
  Celebration._();

  static const _colors = [
    MiraiTokens.accent,
    MiraiTokens.success,
    MiraiTokens.info,
    MiraiTokens.warning,
  ];

  static void show(BuildContext context, {CelebrationSize size = CelebrationSize.medium}) {
    if (!kIsWeb) {
      HapticFeedback.mediumImpact();
    }
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _CelebrationOverlay(
        size: size,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _CelebrationOverlay extends StatefulWidget {
  const _CelebrationOverlay({required this.size, required this.onDone});

  final CelebrationSize size;
  final VoidCallback onDone;

  @override
  State<_CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<_CelebrationOverlay> {
  late final ConfettiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ConfettiController(duration: const Duration(milliseconds: 800));
    _controller.play();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.size == CelebrationSize.large ? 40 : 24;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConfettiWidget(
          confettiController: _controller,
          blastDirection: math.pi / 2,
          blastDirectionality: BlastDirectionality.explosive,
          numberOfParticles: count,
          maxBlastForce: 20,
          minBlastForce: 8,
          gravity: 0.3,
          shouldLoop: false,
          colors: Celebration._colors,
        ),
      ),
    );
  }
}
