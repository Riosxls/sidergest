import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../entities.dart';
import 'models.dart';

class DashAlert {
  const DashAlert(this.module, this.icon, this.label, this.count, this.navId, this.filter, this.onTap);

  final String module;
  final IconData icon;
  final String label;
  final int count;
  final String navId;
  final String? filter;
  final void Function()? onTap;
}

class DashModuleCard extends StatelessWidget {
  const DashModuleCard(this.info, this.metric, this.metricLabel, this.badge, this.onTap, {super.key});

  static const height = 160.0;

  final ModuleInfo info;
  final int? metric;
  final String metricLabel;
  final int badge;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      label: '${info.title}: ${metric ?? 'indisponível'} $metricLabel',
      excludeSemantics: true,
      child: Card(
        key: ValueKey('module-card-${info.id}'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: dashCardShape(context),
        color: cs.surfaceContainerHigh,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(info.icon, size: 28, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(info.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (badge > 0)
                      Container(
                        key: ValueKey('module-badge-${info.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          '$badge',
                          style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ],
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: metric == null
                        ? Text('Indisponível', style: TextStyle(color: cs.onSurfaceVariant))
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$metric',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(metricLabel, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                              ],
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

class DashGridItem {
  const DashGridItem(this.child) : span = 1, height = DashTile.height;
  const DashGridItem.panel(this.child) : span = 2, height = DashBarPanel.height;
  const DashGridItem.sized(this.child, this.height) : span = 1;

  final Widget child;
  final int span;
  final double height;
}

class DashGrid extends StatelessWidget {
  const DashGrid({super.key, required this.items, this.minColumn = 180});

  static const gap = 12.0;

  final double minColumn;
  final List<DashGridItem> items;

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

class DashBarPanel extends StatelessWidget {
  const DashBarPanel({super.key, required this.title, required this.data, this.max});

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
                padding: const EdgeInsets.symmetric(vertical: 4),
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
