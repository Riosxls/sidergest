import 'package:flutter/material.dart';

/// Centers a settings-style page and caps its width so label/value pairs stay close together on wide windows.
class PageColumn extends StatelessWidget {
  const PageColumn({super.key, required this.child, this.maxWidth = 1100});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
