import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard shortcuts of a record page: F5 reloads it (a desktop has no pull-to-refresh) and Ctrl+P prints it.
///
/// Holds focus for the page so the keys work as soon as it opens; a dialog or a text field on top takes the keys first.
class RecordShortcuts extends StatelessWidget {
  const RecordShortcuts({super.key, required this.onRefresh, this.onPrint, required this.child});

  final VoidCallback onRefresh;
  final VoidCallback? onPrint;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.f5): onRefresh, const SingleActivator(LogicalKeyboardKey.keyP, control: true): ?onPrint},
    child: Focus(autofocus: true, skipTraversal: true, child: child),
  );
}
