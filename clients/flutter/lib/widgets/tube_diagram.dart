import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The measure of a tube a form field stands for.
enum TubeMeasure { diameter, width, height, thickness, length }

/// The section of the tube: a round one, or an oblong one (flat oval: two flat sides and half-round ends).
enum TubeProfile { round, oblong }

/// Technical-style drawing of a tube (cross section and side view) with a dimension line for each measure, so a person can see what
/// "diâmetro", "espessura" and "comprimento" refer to. The typed values show on the lines; the [highlight]ed measure (the field being edited) is drawn strong.
class TubeDiagram extends StatelessWidget {
  const TubeDiagram({super.key, this.profile = TubeProfile.round, this.diameter = '', this.width = '', this.height = '', this.thickness = '', this.length = '', this.highlight});

  final TubeProfile profile;

  /// What was typed in each field (shown as is); an empty text shows the letter of the measure instead.
  final String diameter, width, height, thickness, length;
  final TubeMeasure? highlight;

  static const size = Size(300, 214);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String say(String v, String fallback) => v.trim().isEmpty ? fallback : '${v.trim()} mm';
    final rest = 'espessura ${say(thickness, 'não informada')}, comprimento ${say(length, 'não informado')}';
    return Semantics(
      label: profile == TubeProfile.oblong
          ? 'Desenho do tubo oblongo: largura ${say(width, 'não informada')}, altura ${say(height, 'não informada')}, $rest'
          : 'Desenho do tubo: diâmetro externo ${say(diameter, 'não informado')}, $rest',
      image: true,
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: CustomPaint(
            key: const ValueKey('tube-diagram'),
            painter: _TubePainter(
              profile: profile,
              diameter: diameter.trim(),
              width: width.trim(),
              height: height.trim(),
              thickness: thickness.trim(),
              length: length.trim(),
              highlight: highlight,
              ink: cs.onSurfaceVariant,
              accent: cs.primary,
              steel: cs.primaryContainer,
              steelEdge: cs.outline,
            ),
          ),
        ),
      ),
    );
  }
}

class _TubePainter extends CustomPainter {
  _TubePainter({
    required this.profile,
    required this.diameter,
    required this.width,
    required this.height,
    required this.thickness,
    required this.length,
    required this.highlight,
    required this.ink,
    required this.accent,
    required this.steel,
    required this.steelEdge,
  });

  final TubeProfile profile;
  final String diameter, width, height, thickness, length;
  final TubeMeasure? highlight;
  final Color ink, accent, steel, steelEdge;

  Color _color(TubeMeasure m) => highlight == m ? accent : ink.withValues(alpha: highlight == null ? 0.85 : 0.6);
  double _stroke(TubeMeasure m) => highlight == m ? 2.2 : 1.2;
  static double? _num(String s) => double.tryParse(s.replaceAll(',', '.'));

  Paint get _edge => Paint()
    ..color = steelEdge
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 300 x 214 sheet and scaled to whatever room there is.
    final k = size.width / TubeDiagram.size.width;
    canvas.save();
    canvas.scale(k, k);
    if (profile == TubeProfile.oblong) {
      _oblongSection(canvas);
    } else {
      _roundSection(canvas);
    }
    _sideView(canvas);
    canvas.restore();
  }

  void _roundSection(Canvas canvas) {
    // A ring whose wall is as thick, in proportion, as the typed values say (kept readable when they are missing).
    const c = Offset(95, 62);
    const r = 42.0;
    final d = _num(diameter);
    final t = _num(thickness);
    var ratio = 0.16;
    if (d != null && t != null && d > 0 && t > 0 && t * 2 < d) ratio = (t / d).clamp(0.05, 0.34);
    final ri = r * (1 - 2 * ratio);
    final ring = Path()
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..addOval(Rect.fromCircle(center: c, radius: ri))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(ring, Paint()..color = steel);
    canvas.drawCircle(c, r, _edge);
    canvas.drawCircle(c, ri, _edge);
    _centreLines(canvas, c, r + 8, r + 8);

    // Diameter: a dimension line under the circle with its extension lines.
    final dy = c.dy + r + 14;
    final dc = _color(TubeMeasure.diameter);
    _extension(canvas, Offset(c.dx - r, c.dy + r - 2), Offset(c.dx - r, dy + 4), dc);
    _extension(canvas, Offset(c.dx + r, c.dy + r - 2), Offset(c.dx + r, dy + 4), dc);
    _arrows(canvas, Offset(c.dx - r, dy), Offset(c.dx + r, dy), dc, _stroke(TubeMeasure.diameter));
    _text(canvas, diameter.isEmpty ? 'Ø' : 'Ø $diameter', Offset(c.dx, dy + 5), dc, TubeMeasure.diameter, center: true, caption: 'diâmetro externo');

    // Thickness: a leader from the wall to a label on the right.
    const a = -math.pi / 4;
    final wallMid = Offset(c.dx + (r + ri) / 2 * math.cos(a), c.dy + (r + ri) / 2 * math.sin(a));
    _thickness(canvas, wallMid, Offset(c.dx + r + 34, c.dy - r + 2));
  }

  void _oblongSection(Canvas canvas) {
    // Outer stadium wd x hd; the proportions follow the typed values when they make sense, else a typical 17 : 6,2.
    const c = Offset(98, 58);
    const wd = 112.0;
    final w = _num(width), h = _num(height), t = _num(thickness);
    var hd = wd * 6.2 / 17;
    if (w != null && h != null && w > 0 && h > 0 && w >= h) hd = (wd * h / w).clamp(22.0, wd);
    var td = hd * 0.23;
    if (h != null && t != null && h > 0 && t > 0 && t * 2 < h) td = (hd * t / h).clamp(3.0, hd * 0.34);
    RRect stadium(double ww, double hh) => RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: ww, height: hh), Radius.circular(hh / 2));
    final outer = stadium(wd, hd), inner = stadium(wd - 2 * td, hd - 2 * td);
    final ring = Path()
      ..addRRect(outer)
      ..addRRect(inner)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(ring, Paint()..color = steel);
    canvas.drawRRect(outer, _edge);
    canvas.drawRRect(inner, _edge);
    _centreLines(canvas, c, wd / 2 + 8, hd / 2 + 8);

    final left = c.dx - wd / 2, right = c.dx + wd / 2, top = c.dy - hd / 2, bottom = c.dy + hd / 2;
    // Width: under the section.
    final wy = bottom + 14;
    final wc = _color(TubeMeasure.width);
    _extension(canvas, Offset(left, bottom - 2), Offset(left, wy + 4), wc);
    _extension(canvas, Offset(right, bottom - 2), Offset(right, wy + 4), wc);
    _arrows(canvas, Offset(left, wy), Offset(right, wy), wc, _stroke(TubeMeasure.width));
    _text(canvas, width.isEmpty ? 'L' : 'L $width', Offset(c.dx, wy + 5), wc, TubeMeasure.width, center: true, caption: 'largura (lado maior)');
    // Height: a vertical dimension line to the right, label beside it.
    final hx = right + 16;
    final hc = _color(TubeMeasure.height);
    _extension(canvas, Offset(right - 2, top), Offset(hx + 4, top), hc);
    _extension(canvas, Offset(right - 2, bottom), Offset(hx + 4, bottom), hc);
    _arrows(canvas, Offset(hx, top), Offset(hx, bottom), hc, _stroke(TubeMeasure.height));
    _text(canvas, height.isEmpty ? 'A' : 'A $height', Offset(hx + 8, c.dy - 12), hc, TubeMeasure.height, caption: 'altura (lado menor)');
    // Thickness: a leader from the top wall to a label above the corner.
    _thickness(canvas, Offset(c.dx + wd / 4, top + td / 2), Offset(hx - 22, top - 38));
  }

  void _thickness(Canvas canvas, Offset wallPoint, Offset labelAt) {
    final tc = _color(TubeMeasure.thickness);
    final leader = Paint()
      ..color = tc
      ..strokeWidth = _stroke(TubeMeasure.thickness)
      ..style = PaintingStyle.stroke;
    canvas.drawLine(labelAt + const Offset(-4, 8), wallPoint, leader);
    canvas.drawCircle(wallPoint, 2.6, Paint()..color = tc);
    _text(canvas, thickness.isEmpty ? 'e' : 'e $thickness', labelAt, tc, TubeMeasure.thickness, caption: 'espessura da parede');
  }

  void _sideView(Canvas canvas) {
    // The tube lying down, with the length under it.
    const x0 = 24.0, x1 = 276.0, top = 154.0, h = 16.0;
    final body = RRect.fromLTRBR(x0, top, x1, top + h, const Radius.circular(3));
    canvas.drawRRect(body, Paint()..color = steel);
    canvas.drawRRect(body, _edge);
    canvas.drawLine(
      const Offset(x0, top + h / 2),
      const Offset(x1, top + h / 2),
      Paint()
        ..color = ink.withValues(alpha: 0.3)
        ..strokeWidth = 0.7,
    );
    const ly = top + h + 14;
    final lc = _color(TubeMeasure.length);
    _extension(canvas, const Offset(x0, top + h + 2), const Offset(x0, ly + 4), lc);
    _extension(canvas, const Offset(x1, top + h + 2), const Offset(x1, ly + 4), lc);
    _arrows(canvas, const Offset(x0, ly), const Offset(x1, ly), lc, _stroke(TubeMeasure.length));
    _text(canvas, length.isEmpty ? 'C' : 'C $length', const Offset((x0 + x1) / 2, ly + 5), lc, TubeMeasure.length, center: true, caption: 'comprimento');
  }

  void _centreLines(Canvas canvas, Offset c, double halfW, double halfH) {
    final centre = Paint()
      ..color = ink.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(c.dx - halfW, c.dy), Offset(c.dx + halfW, c.dy), centre);
    canvas.drawLine(Offset(c.dx, c.dy - halfH), Offset(c.dx, c.dy + halfH), centre);
  }

  void _extension(Canvas canvas, Offset a, Offset b, Color color) => canvas.drawLine(
    a,
    b,
    Paint()
      ..color = color
      ..strokeWidth = 0.9,
  );

  void _arrows(Canvas canvas, Offset a, Offset b, Color color, double strokeWidth) {
    final p = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
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
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: 13, fontWeight: strong ? FontWeight.w800 : FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cap = TextPainter(
      text: TextSpan(
        text: caption,
        style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 9.5),
      ),
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
      old.profile != profile ||
      old.diameter != diameter ||
      old.width != width ||
      old.height != height ||
      old.thickness != thickness ||
      old.length != length ||
      old.highlight != highlight ||
      old.ink != ink ||
      old.accent != accent ||
      old.steel != steel;
}
