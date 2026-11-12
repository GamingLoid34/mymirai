import 'package:flutter/widgets.dart';

/// Material 3 breakpoints för adaptiva layouter.
/// Tab S9 FE (i landskap) = expanded; mobil = compact.
enum MiraiWindowSize {
  compact,
  medium,
  expanded,
  large;

  bool get isAtLeastMedium =>
      this == MiraiWindowSize.medium ||
      this == MiraiWindowSize.expanded ||
      this == MiraiWindowSize.large;

  bool get isAtLeastExpanded =>
      this == MiraiWindowSize.expanded || this == MiraiWindowSize.large;
}

MiraiWindowSize miraiWindowSizeOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 1200) return MiraiWindowSize.large;
  if (w >= 840) return MiraiWindowSize.expanded;
  if (w >= 600) return MiraiWindowSize.medium;
  return MiraiWindowSize.compact;
}

/// Standardbredd på "läsbar" innehållskolumn per breakpoint.
/// `wide` används för vyer som vinner på mer luft (listor, hem-grid, källpaneler).
class MiraiContentWidth {
  MiraiContentWidth._();
  static double standard(MiraiWindowSize s) {
    switch (s) {
      case MiraiWindowSize.compact:
        return 600;
      case MiraiWindowSize.medium:
        return 720;
      case MiraiWindowSize.expanded:
        return 880;
      case MiraiWindowSize.large:
        return 1040;
    }
  }

  static double wide(MiraiWindowSize s) {
    switch (s) {
      case MiraiWindowSize.compact:
        return 600;
      case MiraiWindowSize.medium:
        return 880;
      case MiraiWindowSize.expanded:
        return 1100;
      case MiraiWindowSize.large:
        return 1280;
    }
  }
}

/// Drop-in-ersättning för `ConstrainedBox(constraints: BoxConstraints(maxWidth: 480), child: ...)`.
/// Behåller exakt samma widget-struktur men sätter `maxWidth` adaptivt.
class MiraiAdaptiveBox extends StatelessWidget {
  const MiraiAdaptiveBox({
    super.key,
    this.constraints = const BoxConstraints(),
    this.wide = false,
    this.child,
  });

  final BoxConstraints constraints;
  final bool wide;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final size = miraiWindowSizeOf(context);
    final maxW = wide
        ? MiraiContentWidth.wide(size)
        : MiraiContentWidth.standard(size);
    return ConstrainedBox(
      constraints: constraints.copyWith(maxWidth: maxW),
      child: child,
    );
  }
}

/// Centraliserad innehållskolumn som ersätter spridda
/// `ConstrainedBox(maxWidth: 480)` så att appen får luft på tablet.
class MiraiContentPanel extends StatelessWidget {
  const MiraiContentPanel({
    super.key,
    required this.child,
    this.wide = false,
    this.alignment = Alignment.topCenter,
  });

  /// Sätt `wide: true` för list-/grid-vyer som mår bra av mer bredd.
  final bool wide;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final size = miraiWindowSizeOf(context);
    final maxW = wide
        ? MiraiContentWidth.wide(size)
        : MiraiContentWidth.standard(size);
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: child,
      ),
    );
  }
}
