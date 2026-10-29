import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../entities.dart';

class GridItem {
  const GridItem(this.child) : span = 1, height = DashTile.height;
  const GridItem.panel(this.child) : span = 2, height = BarPanel.height;

  final Widget child;
  final int span;
  final double height;
}

class DashGrid extends StatelessWidget {
  const DashGrid({super.key, required this.items});

  static const gap = 12.0;
  static const minColumn = 180.0;

  final List<GridItem> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = math.max(1, ((c.maxWidth + gap) / (minColumn + gap)).floor());
      final colWidth = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final i in items)
            SizedBox(
              width: (() {
                final span = math.min(i.span, cols);
                return colWidth * span + gap * (span - 1) - 0.01;
              })(),
              height: i.height,
              child: i.child,
            ),
        ],
      );
    },
  );
}

ShapeBorder dashCardShape(BuildContext context) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
);

class DashTile extends StatelessWidget {
  const DashTile({super.key, required this.icon, required this.label, required this.value, this.alert = false, this.onTap});

  static const height = 104.0;

  final IconData icon;
  final String label;
  final String value;
  final bool alert;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = alert ? cs.onErrorContainer : null;
    return Semantics(
      button: onTap != null,
      label: '$value $label',
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: dashCardShape(context),
        color: alert ? cs.errorContainer : cs.surfaceContainerHigh,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(alert ? Icons.error_outline : icon, size: 20, color: alert ? cs.onErrorContainer : cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: label,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                        ),
                      ),
                    ),
                    if (onTap != null) Icon(Icons.chevron_right, size: 18, color: fg ?? cs.onSurfaceVariant),
                  ],
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: fg,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashNotice extends StatelessWidget {
  const DashNotice({super.key, required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: dashCardShape(context),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BarPanel extends StatelessWidget {
  const BarPanel({super.key, required this.title, required this.data, this.max});

  static const height = 268.0;

  final String title;
  final Map<String, num> data;
  final num? max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = data.entries.take(8).toList();
    final top = max ?? rows.fold<num>(1, (m, e) => e.value > m ? e.value : m);
    return Card(
      margin: EdgeInsets.zero,
      shape: dashCardShape(context),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Expanded(
                child: Center(
                  child: Text('Sem dados ainda', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
            for (final e in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 120, child: Text(e.key, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (e.value / top).clamp(0, 1).toDouble(),
                          child: Container(
                            height: 16,
                            decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        fmtNum(e.value, e.value is int ? 0 : 1),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
