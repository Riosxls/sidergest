import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The measure of a round tube a form field stands for.
enum TubeMeasure { diameter, thickness, length }

/// Technical-style drawing of a round tube (cross section and side view) with a dimension line for each measure, so a person can see what
/// "diâmetro", "espessura" and "comprimento" refer to. The typed values show on the lines; the [highlight]ed measure (the field being edited) is drawn strong.
class TubeDiagram extends StatelessWidget {
  const TubeDiagram({super.key, this.diameter = '', this.thickness = '', this.length = '', this.highlight});

  /// What was typed in each field (shown as is); an empty text shows the letter of the measure instead.
  final String diameter, thickness, length;
  final TubeMeasure? highlight;

  static const size = Size(300, 214);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String say(String v, String fallback) => v.trim().isEmpty ? fallback : '${v.trim()} mm';
    return Semantics(
      label: 'Desenho do tubo: diâmetro externo ${say(diameter, 'não informado')}, espessura ${say(thickness, 'não informada')}, comprimento ${say(length, 'não informado')}',
      image: true,
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: CustomPaint(
            key: const ValueKey('tube-diagram'),
            painter: _TubePainter(
              diameter: diameter.trim(),
              thickness: thickness.trim(),
              length: length.trim(),
              highlight: highlight,
              ink: cs.onSurfaceVariant,
              accent: cs.primary,
              steel: cs.primaryContainer,
              steelEdge: cs.outline,
              paper: cs.surface,
            ),
          ),
        ),
      ),
    );
  }
}

class _TubePainter extends CustomPainter {
  _TubePainter({
    required this.diameter,
    required this.thickness,
    required this.length,
    required this.highlight,
    required this.ink,
    required this.accent,
    required this.steel,
    required this.steelEdge,
    required this.paper,
  });

  final String diameter, thickness, length;
  final TubeMeasure? highlight;
  final Color ink, accent, steel, steelEdge, paper;

  Color _color(TubeMeasure m) => highlight == m ? accent : ink.withValues(alpha: highlight == null ? 0.85 : 0.6);
  double _width(TubeMeasure m) => highlight == m ? 2.2 : 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 300 x 214 sheet and scaled to whatever room there is.
    final k = size.width / TubeDiagram.size.width;
    canvas.save();
    canvas.scale(k, k);

    // Cross section: a ring whose wall is as thick, in proportion, as the typed values say (kept readable when they are missing).
    const c = Offset(95, 62);
    const r = 42.0;
    final d = double.tryParse(diameter.replaceAll(',', '.'));
    final t = double.tryParse(thickness.replaceAll(',', '.'));
    var ratio = 0.16;
    if (d != null && t != null && d > 0 && t > 0 && t * 2 < d) ratio = (t / d).clamp(0.05, 0.34);
    final ri = r * (1 - 2 * ratio);
    final ring = Path()
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..addOval(Rect.fromCircle(center: c, radius: ri))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(ring, Paint()..color = steel);
    final edge = Paint()
      ..color = steelEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(c, r, edge);
    canvas.drawCircle(c, ri, edge);
    // Centre lines.
    final centre = Paint()
      ..color = ink.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(c.dx - r - 8, c.dy), Offset(c.dx + r + 8, c.dy), centre);
    canvas.drawLine(Offset(c.dx, c.dy - r - 8), Offset(c.dx, c.dy + r + 8), centre);

    // Diameter: a dimension line under the circle with its extension lines.
    final dy = c.dy + r + 14;
    final dc = _color(TubeMeasure.diameter);
    final ext = Paint()
      ..color = dc
      ..strokeWidth = 0.9;
    canvas.drawLine(Offset(c.dx - r, c.dy + r - 2), Offset(c.dx - r, dy + 4), ext);
    canvas.drawLine(Offset(c.dx + r, c.dy + r - 2), Offset(c.dx + r, dy + 4), ext);
    _arrows(canvas, Offset(c.dx - r, dy), Offset(c.dx + r, dy), dc, _width(TubeMeasure.diameter));
    _text(canvas, diameter.isEmpty ? 'Ø' : 'Ø $diameter', Offset(c.dx, dy + 5), dc, TubeMeasure.diameter, center: true, caption: 'diâmetro externo');

    // Thickness: a leader from the wall to a label on the right.
    final tc = _color(TubeMeasure.thickness);
    const a = -math.pi / 4;
    final wallMid = Offset(c.dx + (r + ri) / 2 * math.cos(a), c.dy + (r + ri) / 2 * math.sin(a));
    final labelAt = Offset(c.dx + r + 34, c.dy - r + 2);
    final leader = Paint()
      ..color = tc
      ..strokeWidth = _width(TubeMeasure.thickness)
      ..style = PaintingStyle.stroke;
    canvas.drawLine(labelAt + const Offset(-4, 8), wallMid, leader);
    canvas.drawCircle(wallMid, 2.6, Paint()..color = tc);
    _text(canvas, thickness.isEmpty ? 'e' : 'e $thickness', labelAt, tc, TubeMeasure.thickness, caption: 'espessura da parede');

    // Side view: the tube lying down, with the length under it.
    const x0 = 24.0, x1 = 276.0, top = 154.0, h = 16.0;
    final body = RRect.fromLTRBR(x0, top, x1, top + h, const Radius.circular(3));
    canvas.drawRRect(body, Paint()..color = steel);
    canvas.drawRRect(body, edge);
    canvas.drawLine(const Offset(x0, top + h / 2), const Offset(x1, top + h / 2), Paint()
      ..color = ink.withValues(alpha: 0.3)
      ..strokeWidth = 0.7);
    const ly = top + h + 14;
    final lc = _color(TubeMeasure.length);
    final extL = Paint()
      ..color = lc
      ..strokeWidth = 0.9;
    canvas.drawLine(const Offset(x0, top + h + 2), const Offset(x0, ly + 4), extL);
    canvas.drawLine(const Offset(x1, top + h + 2), const Offset(x1, ly + 4), extL);
    _arrows(canvas, const Offset(x0, ly), const Offset(x1, ly), lc, _width(TubeMeasure.length));
    _text(canvas, length.isEmpty ? 'C' : 'C $length', const Offset((x0 + x1) / 2, ly + 5), lc, TubeMeasure.length, center: true, caption: 'comprimento');
    canvas.restore();
  }

  void _arrows(Canvas canvas, Offset a, Offset b, Color color, double width) {
    final p = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, p);
    final dir = (b - a) / (b - a).distance;
    final n = Offset(-dir.dy, dir.dx);
    for (final (tip, s) in [(a, 1.0), (b, -1.0)]) {
      final base = tip + dir * (7 * s);
      final tri = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + n.dx * 2.8, base.dy + n.dy * 2.8)
        ..lineTo(base.dx - n.dx * 2.8, base.dy - n.dy * 2.8)
        ..close();
      canvas.drawPath(tri, Paint()..color = color);
    }
  }

  void _text(Canvas canvas, String value, Offset at, Color color, TubeMeasure m, {bool center = false, required String caption}) {
    final strong = highlight == m;
    final main = TextPainter(
      text: TextSpan(text: value, style: TextStyle(color: color, fontSize: 13, fontWeight: strong ? FontWeight.w800 : FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    final cap = TextPainter(
      text: TextSpan(text: caption, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 9.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = math.max(main.width, cap.width);
    var x = center ? at.dx - w / 2 : at.dx;
    // Keep the label on the sheet.
    x = x.clamp(0.0, TubeDiagram.size.width - w);
    main.paint(canvas, Offset(x + (center ? (w - main.width) / 2 : 0), at.dy));
    cap.paint(canvas, Offset(x + (center ? (w - cap.width) / 2 : 0), at.dy + main.height - 1));
  }

  @override
  bool shouldRepaint(_TubePainter old) =>
      old.diameter != diameter || old.thickness != thickness || old.length != length || old.highlight != highlight || old.ink != ink || old.accent != accent || old.steel != steel;
}
