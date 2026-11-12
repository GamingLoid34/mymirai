import 'package:flutter/material.dart';

import '../theme/mirai_tokens.dart';

/// Flytande "+N ⭐"-chip som stiger och tonar ut. Kortlivad overlay, ingen
/// state hos anropande skärm.
class XpChip {
  XpChip._();

  static void show(BuildContext context, int amount) {
    if (amount <= 0) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _XpChipOverlay(
        amount: amount,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _XpChipOverlay extends StatefulWidget {
  const _XpChipOverlay({required this.amount, required this.onDone});

  final int amount;
  final VoidCallback onDone;

  @override
  State<_XpChipOverlay> createState() => _XpChipOverlayState();
}

class _XpChipOverlayState extends State<_XpChipOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rise;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _rise = Tween<double>(begin: 0, end: -60).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _fade = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0)),
    );
    _controller.forward().whenComplete(() {
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
    final tt = Theme.of(context).textTheme;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _rise.value),
              child: Opacity(opacity: _fade.value, child: child),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: MiraiTokens.accent,
                borderRadius: BorderRadius.circular(MiraiTokens.radiusPill),
                boxShadow: MiraiTokens.shadowMd,
              ),
              child: Text(
                '+${widget.amount} ⭐',
                style: tt.titleMedium?.copyWith(
                  color: MiraiTokens.textInverse,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
