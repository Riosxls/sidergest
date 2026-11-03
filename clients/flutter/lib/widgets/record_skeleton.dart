import 'package:flutter/material.dart';

/// Placeholder shown while a record page loads: the shape of the page (header, path bar, next-step card, a table) in quiet blocks, so the
/// layout does not jump when the data arrives. Announced to screen readers as "Carregando".
class RecordSkeleton extends StatelessWidget {
  const RecordSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block(double height, {double? width, double radius = 10}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
    );
    return Semantics(
      label: 'Carregando',
      liveRegion: true,
      excludeSemantics: true,
      child: ListView(
        key: const ValueKey('record-skeleton'),
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [block(112), const SizedBox(height: 12), block(44), const SizedBox(height: 12), block(96), const SizedBox(height: 12), block(220)],
      ),
    );
  }
}
