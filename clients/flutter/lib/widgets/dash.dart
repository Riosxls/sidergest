import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../entities.dart';
import 'responsive.dart';

/// A cell of [DashGrid]: one column wide by default, [GridItem.panel] and [GridItem.bars] span two.
class GridItem {
  const GridItem(this.child) : span = 1, height = DashTile.height;
  const GridItem.panel(this.child, {this.height = BarPanel.height}) : span = 2;

  /// A bar panel sized to its rows, so a short chart does not sit in a tall empty card.
  GridItem.bars(BarPanel panel) : child = panel, span = 2, height = BarPanel.heightFor(panel.data.length);

  final Widget child;
  final int span;
  final double height;
}

/// Responsive grid of dashboard tiles and panels.
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
              height: math.max(i.height, scaledHeight(context, i.height)),
              child: i.child,
            ),
        ],
      );
    },
  );
}

/// Pull-to-refresh on touch platforms only. On desktop a mouse drag at the top would pull the whole page down and leave a gap and a spinner
/// above the title; the refresh button and F5 cover desktop.
class PullRefresh extends StatelessWidget {
  const PullRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final desktop = const {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS}.contains(Theme.of(context).platform);
    return desktop ? child : RefreshIndicator(onRefresh: onRefresh, child: child);
  }
}

ShapeBorder dashCardShape(BuildContext context) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
);

/// Dashboard card with an icon, a [value] and a [label]; [alert] highlights it.
class DashTile extends StatelessWidget {
  const DashTile({super.key, required this.icon, required this.label, required this.value, this.hint, this.alert = false, this.onTap});

  static const height = 112.0;

  final IconData icon;
  final String label;
  final String value;

  /// Secondary figure beside [value], e.g. the amount behind a count.
  final String? hint;
  final bool alert;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = alert ? cs.error : null;
    // A zero that is not an alarm steps back so the numbers that matter stand out.
    final valueColor = fg ?? (value == '0' ? cs.onSurfaceVariant : null);
    return Semantics(
      button: onTap != null,
      label: hint == null ? '$value $label' : '$value $label, $hint',
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: alert
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
              )
            : dashCardShape(context),
        color: cs.surfaceContainerHigh,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // The tile keeps its own icon (it says what the number is); the alert state is a badge on it, not a different glyph.
                    Badge(isLabelVisible: alert, smallSize: 8, backgroundColor: cs.error, child: Icon(icon, size: 20, color: alert ? cs.error : cs.primary)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: label,
                        child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            value,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: valueColor,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (hint != null) ...[
                            const SizedBox(width: 8),
                            Text(hint!, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          ],
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

/// Full width dashboard message with an icon, a [title] and a [subtitle].
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

/// Dashboard panel with a horizontal bar per row of [data]; [warn] marks rows to highlight.
class BarPanel extends StatelessWidget {
  const BarPanel({super.key, required this.title, required this.data, this.max, this.emptyText = 'Sem dados ainda', this.warn = const {}, this.onRowTap});

  static const height = 268.0;
  static const maxRows = 10;
  static const _rowHeight = 34.0;

  /// Panel height for [rows] bars: padding, title and one slot per row; an empty panel is just a short message.
  static double heightFor(int rows) => rows == 0 ? 120 : 84 + rows.clamp(1, maxRows) * _rowHeight;

  final String title;
  final Map<String, num> data;
  final num? max;

  /// What to say when there is nothing to draw: name what is missing, not just "no data".
  final String emptyText;

  /// Row labels drawn in the error colour (a bucket that is a problem, like products with no operations).
  final Set<String> warn;

  /// Makes every row tappable; receives the row label.
  final void Function(String label)? onRowTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = data.entries.take(maxRows).toList();
    final top = max ?? rows.fold<num>(1, (m, e) => e.value > m ? e.value : m);
    return LayoutBuilder(builder: (context, box) => Card(
      margin: EdgeInsets.zero,
      shape: dashCardShape(context),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One line, so the panel height computed from its row count always holds (a narrow phone would otherwise wrap the title and overflow).
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            for (final e in rows)
              InkWell(
                onTap: onRowTap == null ? null : () => onRowTap!(e.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: (box.maxWidth * 0.35).clamp(90.0, 150.0),
                        child: Tooltip(
                          message: e.key,
                          child: Text(e.key, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (e.value / top).clamp(0, 1).toDouble(),
                            child: Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: warn.contains(e.key) ? theme.colorScheme.error : theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
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
              ),
          ],
        ),
      ),
    ));
  }
}
