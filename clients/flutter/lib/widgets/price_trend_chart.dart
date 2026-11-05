import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../entities.dart';
import '../theme_tokens.dart';

/// One month of the price history: the median R$/kg of the sales of that month and how many sales it came from.
class TrendPoint {
  const TrendPoint(this.month, this.price, this.count);

  /// "yyyy-MM".
  final String month;
  final double price;
  final int count;

  /// Months since year 0, so gaps between points are drawn in proportion.
  int get index {
    final p = month.split('-');
    if (p.length < 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 12 + (int.tryParse(p[1]) ?? 1) - 1;
  }

  /// "mar/26".
  String get short => _label(index, short: true);

  /// "mar/2026".
  String get long => _label(index, short: false);

  static const _names = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

  static String _label(int index, {required bool short}) {
    final y = index ~/ 12, m = index % 12;
    return '${_names[m]}/${short ? '${y % 100}'.padLeft(2, '0') : y}';
  }

  /// Reads the `trend` / `customerTrend` list of the API; rows that are not understood are left out. Oldest first.
  static List<TrendPoint> parse(Object? raw) {
    final out = <TrendPoint>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e['month'], p = e['pricePerKg'];
        if (m is! String || p is! num) continue;
        out.add(TrendPoint(m, p.toDouble(), (e['count'] as num?)?.toInt() ?? 0));
      }
    }
    out.sort((a, b) => a.index.compareTo(b.index));
    return out;
  }
}

/// "sobe de R$ 19 para R$ 23 em 24 meses": the whole movement of [points] (oldest first) in one sentence, for people who cannot see the chart.
String trendSummary(List<TrendPoint> points) {
  if (points.length < 2) return '';
  final a = points.first, b = points.last;
  final months = b.index - a.index;
  final span = months == 1 ? '1 mês' : '$months meses';
  final change = (b.price - a.price) / a.price;
  String money(double v, bool cents) => 'R\$ ${fmtNum(v, cents ? 2 : 0)}';
  final cents = (a.price.round() - b.price.round()).abs() < 2;
  if (change.abs() < 0.01) return 'fica estável em ${money(b.price, true)} em $span';
  return '${change > 0 ? 'sobe' : 'cai'} de ${money(a.price, cents)} para ${money(b.price, cents)} em $span';
}

/// Compact line chart of the price per kg over the months, drawn by hand (no chart package). The market line is [points]; [customerPoints] adds a
/// second line for the chosen customer. Hover or tap shows the month, the price and how many sales it came from. Hidden below [minPoints] points.
class PriceTrendChart extends StatefulWidget {
  const PriceTrendChart({
    super.key,
    required this.points,
    this.customerPoints = const [],
    this.title = 'R\$/kg ao longo do tempo',
    this.primaryLabel = 'Mercado',
    this.customerLabel = 'Este cliente',
    this.minPoints = 3,
    this.height = 190,
  });

  final List<TrendPoint> points, customerPoints;
  final String title, primaryLabel, customerLabel;
  final int minPoints;
  final double height;

  @override
  State<PriceTrendChart> createState() => _PriceTrendChartState();
}

class _PriceTrendChartState extends State<PriceTrendChart> {
  static const _left = 46.0, _right = 10.0, _top = 10.0, _bottom = 22.0;
  int? _hover; // index into widget.points

  void _pick(Offset p, double width) {
    final pts = widget.points;
    if (pts.isEmpty) return;
    final lo = pts.first.index, hi = pts.last.index;
    final plotW = width - _left - _right;
    final t = hi == lo ? 0.0 : ((p.dx - _left) / plotW).clamp(0.0, 1.0);
    final target = lo + t * (hi - lo);
    var best = 0;
    for (var i = 1; i < pts.length; i++) {
      if ((pts[i].index - target).abs() < (pts[best].index - target).abs()) best = i;
    }
    if (best != _hover) setState(() => _hover = best);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts.length < widget.minPoints) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final summary = trendSummary(pts);
    final hasCustomer = widget.customerPoints.isNotEmpty;
    final hover = _hover != null && _hover! < pts.length ? pts[_hover!] : null;
    TrendPoint? customerAt;
    if (hover != null) {
      for (final c in widget.customerPoints) {
        if (c.index == hover.index) customerAt = c;
      }
    }
    return Column(
      key: const ValueKey('price-trend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            _legend(cs.primary, widget.primaryLabel, theme),
            if (hasCustomer) _legend(cs.tertiary, widget.customerLabel, theme),
          ],
        ),
        if (summary.isNotEmpty)
          Text(
            'Preço por kg $summary.',
            key: const ValueKey('price-trend-summary'),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            return SizedBox(
              height: widget.height,
              child: Semantics(
                label: 'Gráfico do preço por kg ao longo do tempo: $summary',
                image: true,
                child: ExcludeSemantics(
                  child: MouseRegion(
                    onHover: (e) => _pick(e.localPosition, width),
                    onExit: (_) => setState(() => _hover = null),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _pick(d.localPosition, width),
                      onHorizontalDragUpdate: (d) => _pick(d.localPosition, width),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              key: const ValueKey('price-trend-canvas'),
                              painter: _TrendPainter(
                                points: pts,
                                customer: widget.customerPoints,
                                hover: _hover,
                                ink: cs.onSurfaceVariant,
                                grid: cs.outlineVariant,
                                line: cs.primary,
                                customerLine: cs.tertiary,
                                label: theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          if (hover != null)
                            Positioned(
                              left: _tipLeft(hover, width),
                              top: 0,
                              child: Container(
                                key: const ValueKey('price-trend-tooltip'),
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                                decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(AppRadius.field)),
                                child: Text(
                                  '${hover.long}: ${fmtMoney(hover.price)}/kg · ${hover.count} ${hover.count == 1 ? 'venda' : 'vendas'}'
                                  '${customerAt == null ? '' : '\n${widget.customerLabel}: ${fmtMoney(customerAt.price)}/kg · ${customerAt.count} ${customerAt.count == 1 ? 'venda' : 'vendas'}'}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onInverseSurface),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// The tooltip sits near the hovered point but never leaves the chart (it is about 230 px wide).
  double _tipLeft(TrendPoint p, double width) {
    final pts = widget.points;
    final lo = pts.first.index, hi = pts.last.index;
    final x = _left + (hi == lo ? 0.5 : (p.index - lo) / (hi - lo)) * (width - _left - _right);
    return (x - 115).clamp(0.0, math.max(0.0, width - 230));
  }

  Widget _legend(Color color, String text, ThemeData theme) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 3,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(text, style: theme.textTheme.bodySmall),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.customer,
    required this.hover,
    required this.ink,
    required this.grid,
    required this.line,
    required this.customerLine,
    required this.label,
  });

  final List<TrendPoint> points, customer;
  final int? hover;
  final Color ink, grid, line, customerLine;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const left = _PriceTrendChartState._left, right = _PriceTrendChartState._right, top = _PriceTrendChartState._top, bottom = _PriceTrendChartState._bottom;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    if (plot.width <= 0 || plot.height <= 0) return;
    final all = [...points, ...customer];
    var lo = all.map((p) => p.price).reduce(math.min), hi = all.map((p) => p.price).reduce(math.max);
    final pad = math.max((hi - lo) * 0.08, hi * 0.01);
    lo -= pad;
    hi += pad;
    final first = points.first.index, last = points.last.index;
    double x(TrendPoint p) => plot.left + (last == first ? 0.5 : (p.index - first) / (last - first)) * plot.width;
    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
    final style = label.copyWith(color: ink, fontSize: 11);

    void text(String s, Offset at, {bool rightAlign = false, bool center = false}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = at.dx;
      if (rightAlign) dx -= tp.width;
      if (center) dx -= tp.width / 2;
      dx = dx.clamp(0.0, math.max(0.0, size.width - tp.width));
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.6;
    for (var i = 0; i < 3; i++) {
      final v = lo + (hi - lo) * i / 2;
      final yy = y(v);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gridPaint);
      text('R\$ ${fmtNum(v, (hi - lo) < 4 ? 1 : 0)}', Offset(plot.left - 4, yy), rightAlign: true);
    }
    final ticks = {0, (points.length - 1) ~/ 2, points.length - 1}.toList()..sort();
    for (final i in ticks) {
      text(points[i].short, Offset(x(points[i]), plot.bottom + 12), center: true);
    }

    void draw(List<TrendPoint> pts, Color color) {
      if (pts.isEmpty) return;
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = Offset(x(pts[i]), y(pts[i].price));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
      if (pts.length <= 36) {
        for (final p in pts) {
          canvas.drawCircle(Offset(x(p), y(p.price)), 2.5, Paint()..color = color);
        }
      }
    }

    draw(points, line);
    draw(customer, customerLine);
    if (hover != null && hover! < points.length) {
      final p = points[hover!];
      canvas.drawLine(
        Offset(x(p), plot.top),
        Offset(x(p), plot.bottom),
        Paint()
          ..color = ink.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(x(p), y(p.price)),
        5,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.points != points || old.customer != customer || old.hover != hover || old.ink != ink || old.line != line;
}
