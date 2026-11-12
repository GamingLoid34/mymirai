import 'package:flutter/material.dart';

import '../models/homework_item.dart';

extension HomeworkStatusVisual on HomeworkStatus {
  /// Mjuka färger utan skarpa signal-färger (NPF-vänligt).
  (Color background, Color foreground) chipColors(ColorScheme scheme) {
    switch (this) {
      case HomeworkStatus.todo:
        return (scheme.secondaryContainer, scheme.onSecondaryContainer);
      case HomeworkStatus.inProgress:
        return (scheme.primaryContainer, scheme.onPrimaryContainer);
      case HomeworkStatus.done:
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer);
      case HomeworkStatus.archived:
        return (
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        );
    }
  }
}
