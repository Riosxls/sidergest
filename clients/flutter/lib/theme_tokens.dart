import 'package:flutter/material.dart';

/// Spacing scale; use these instead of raw numbers in padding and gaps.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii.
abstract final class AppRadius {
  static const double field = 4;
  static const double chip = 8;
  static const double card = 12;
  static const double pill = 999;
}

/// Smallest comfortable touch target.
const double kMinTouchTarget = 44;

/// Filled button for destructive actions (cancel, delete, reverse): error colour with readable text in both themes.
ButtonStyle dangerButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError);
}
