import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../entities.dart' show parseDecimal;

/// The measure of a tube a form field stands for. For a rectangular tube [width] is side A (horizontal) and [height] side B (vertical).
enum TubeMeasure { diameter, width, height, thickness, length }

/// The section of the tube: a round one, an oblong one (flat oval: two flat sides and half-round ends) or a rectangular one (square when the sides are equal).
enum TubeProfile { round, oblong, rectangular }

/// Technical-style drawing of a tube (cross section and side view) with a dimension line for each measure, so a person can see what
/// "diâmetro", "espessura" and "comprimento" refer to. The typed values show on the lines; the [highlight]ed measure (the field being edited) is drawn strong.
///
/// The drawing moves: the section morphs between round and oblong, the wall and the proportions glide to the typed values, and the
/// highlight fades from one measure to the next. With "remove animations" on in the system, it jumps instead.
class TubeDiagram extends StatefulWidget {
  const TubeDiagram({
    super.key,
    this.profile = TubeProfile.round,
    this.diameter = '',
    this.width = '',
    this.height = '',
    this.thickness = '',
    this.length = '',
    this.highlight,
  });

  final TubeProfile profile;

  /// What was typed in each field (shown as is); an empty text shows the letter of the measure instead.
  final String diameter, width, height, thickness, length;
  final TubeMeasure? highlight;

  static const size = Size(300, 214);

  /// A typed measure read like the form fields read it ("1.500" is 1500, "1,5" is 1.5), so the drawing never contradicts what is sent.
  @visibleForTesting
  static double? parseMeasure(String s) => parseDecimal(s.trim())?.toDouble();

  @override
  State<TubeDiagram> createState() => _TubeDiagramState();
}

/// The proportions of the section on the sheet (all in sheet units): outer width and height, wall, how far from round it is (0 round, 1 not
/// round) and the radius of the outer corners (half the height for round and oblong sections, small for a rectangular one).
class _Geo {
  const _Geo(this.morph, this.w, this.h, this.td, this.r);

  final double morph, w, h, td, r;

  static _Geo lerp(_Geo a, _Geo b, double t) =>
      _Geo(a.morph + (b.morph - a.morph) * t, a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t, a.td + (b.td - a.td) * t, a.r + (b.r - a.r) * t);

  @override
  bool operator ==(Object other) => other is _Geo && other.morph == morph && other.w == w && other.h == h && other.td == td && other.r == r;

  @override
  int get hashCode => Object.hash(morph, w, h, td, r);
}

class _TubeDiagramState extends State<TubeDiagram> with TickerProviderStateMixin {
  static const _round = 88.0, _wide = 116.0;

  late final AnimationController _shape = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _focus = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  late _Geo _from = _target(), _to = _from;
  TubeMeasure? _previous;

  /// Read like the form fields read them ("1.500" is 1500, "1,5" is 1.5), so the drawing never contradicts what is sent.
  static double? _num(String s) => TubeDiagram.parseMeasure(s);

  _Geo _target() {
    final t = _num(widget.thickness);
    if (widget.profile == TubeProfile.oblong) {
      final w = _num(widget.width), h = _num(widget.height);
      var hd = _wide * 6.2 / 17;
      if (w != null && h != null && w > 0 && h > 0 && w >= h) hd = (_wide * h / w).clamp(24.0, 72.0);
      var td = hd * 0.23;
      if (h != null && t != null && h > 0 && t > 0 && t * 2 < h) td = (hd * t / h).clamp(3.0, hd * 0.34);
      return _Geo(1, _wide, hd, td, hd / 2);
    }
    if (widget.profile == TubeProfile.rectangular) {
      // Side A is horizontal, side B vertical; the larger of the two takes the room, in the proportion typed.
      final a = _num(widget.width), b = _num(widget.height);
      var w = 100.0, h = 66.0;
      if (a != null && b != null && a > 0 && b > 0) {
        final k = math.min(_wide / a, 72 / b);
        w = (a * k).clamp(24.0, _wide);
        h = (b * k).clamp(24.0, 72.0);
      }
      final side = math.min(a ?? 1, b ?? 1) > 0 ? math.min(a ?? 1, b ?? 1) : 1.0;
      var td = math.min(w, h) * 0.16;
      if (a != null && b != null && t != null && t > 0 && t * 2 < side) td = (math.min(w, h) * t / side).clamp(3.0, math.min(w, h) * 0.34);
      return _Geo(1, w, h, td, 5);
    }
    final d = _num(widget.diameter);
    var ratio = 0.16;
    if (d != null && t != null && d > 0 && t > 0 && t * 2 < d) ratio = (t / d).clamp(0.05, 0.34);
    return _Geo(0, _round, _round, _round * ratio, _round / 2);
  }

  _Geo get _now => _Geo.lerp(_from, _to, Curves.easeOutCubic.transform(_shape.value));

  @override
  void didUpdateWidget(TubeDiagram old) {
    super.didUpdateWidget(old);
    final target = _target();
    if (target != _to) {
      _from = _now;
      _to = target;
      _shape.duration = _animations ? Duration(milliseconds: widget.profile != old.profile ? 420 : 260) : Duration.zero;
      _shape.forward(from: 0);
    }
    if (widget.highlight != old.highlight) {
      _previous = old.highlight;
      _focus.duration = _animations ? const Duration(milliseconds: 220) : Duration.zero;
      _focus.forward(from: 0);
    }
  }

  bool get _animations => !MediaQuery.disableAnimationsOf(context);

  @override
  void dispose() {
    _shape.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String say(String v, String fallback) => v.trim().isEmpty ? fallback : '${v.trim()} mm';
    final rest = 'espessura ${say(widget.thickness, 'não informada')}, comprimento ${say(widget.length, 'não informado')}';
    return Semantics(
      label: switch (widget.profile) {
        TubeProfile.oblong => 'Desenho do tubo oblongo: largura ${say(widget.width, 'não informada')}, altura ${say(widget.height, 'não informada')}, $rest',
        TubeProfile.rectangular =>
          'Desenho do tubo retangular: lado A ${say(widget.width, 'não informado')}, lado B ${say(widget.height, 'não informado')}, $rest',
        TubeProfile.round => 'Desenho do tubo: diâmetro externo ${say(widget.diameter, 'não informado')}, $rest',
      },
      image: true,
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: TubeDiagram.size.width / TubeDiagram.size.height,
          child: AnimatedBuilder(
            animation: Listenable.merge([_shape, _focus]),
            builder: (context, _) => CustomPaint(
              key: const ValueKey('tube-diagram'),
              painter: _TubePainter(
                geo: _now,
                rectangular: widget.profile == TubeProfile.rectangular,
                diameter: widget.diameter.trim(),
                width: widget.width.trim(),
                height: widget.height.trim(),
                thickness: widget.thickness.trim(),
                length: widget.length.trim(),
                highlight: widget.highlight,
                previous: _previous,
                focusT: Curves.easeOut.transform(_focus.value),
                ink: cs.onSurfaceVariant,
                accent: cs.primary,
                steel: cs.primaryContainer,
                steelEdge: cs.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TubePainter extends CustomPainter {
  _TubePainter({
    required this.geo,
    required this.rectangular,
    required this.diameter,
    required this.width,
    required this.height,
    required this.thickness,
    required this.length,
    required this.highlight,
    required this.previous,
    required this.focusT,
    required this.ink,
    required this.accent,
    required this.steel,
    required this.steelEdge,
  });

  final _Geo geo;
  final bool rectangular;
  final String diameter, width, height, thickness, length;
  final TubeMeasure? highlight, previous;
  final double focusT;
  final Color ink, accent, steel, steelEdge;

  /// How strongly [m] is highlighted now (0..1): it fades in when the field gets focus and out when it loses it.
  double _hw(TubeMeasure m) => math.max(highlight == m ? focusT : 0.0, previous == m && highlight != m ? 1 - focusT : 0.0);

  Color _color(TubeMeasure m, [double alpha = 1]) {
    final h = _hw(m);
    final base = ink.withValues(alpha: highlight == null && previous == null ? 0.85 : 0.6);
    return Color.lerp(base, accent, h)!.withValues(alpha: alpha * Color.lerp(base, accent, h)!.a);
  }

  double _stroke(TubeMeasure m) => 1.3 + 1.1 * _hw(m);

  Paint get _edge => Paint()
    ..color = steelEdge
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 300 x 214 sheet and scaled to whatever room there is.
    final k = size.width / TubeDiagram.size.width;
    canvas.save();
    canvas.scale(k, k);
    _section(canvas);
    _sideView(canvas);
    canvas.restore();
  }

  void _section(Canvas canvas) {
    // A tall oblong section sinks a little so the wall label above it stays on the sheet.
    final c = Offset(100 - 6 * geo.morph, 58 + geo.morph * math.max(0.0, 40 + geo.h / 2 - 58));
    final w = geo.w, h = geo.h, td = geo.td;
    // Outer corners of radius r (half the height when round or oblong, small when rectangular); the inner ones are a wall thinner.
    RRect rounded(double ww, double hh, double r) =>
        RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: ww, height: hh), Radius.circular(math.max(0.0, math.min(r, math.min(ww, hh) / 2))));
    final outer = rounded(w, h, geo.r), inner = rounded(w - 2 * td, h - 2 * td, math.max(geo.r - td, 1.5));
    final ring = Path()
      ..addRRect(outer)
      ..addRRect(inner)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(ring, Paint()..color = steel);
    canvas.drawRRect(outer, _edge);
    canvas.drawRRect(inner, _edge);
    final centre = Paint()
      ..color = ink.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(c.dx - w / 2 - 8, c.dy), Offset(c.dx + w / 2 + 8, c.dy), centre);
    canvas.drawLine(Offset(c.dx, c.dy - h / 2 - 8), Offset(c.dx, c.dy + h / 2 + 8), centre);

    final left = c.dx - w / 2, right = c.dx + w / 2, top = c.dy - h / 2, bottom = c.dy + h / 2;
    final m = geo.morph;

    // The line under the section: the diameter of a round tube, the width of an oblong one (the same line, the label changes).
    final wy = bottom + 15;
    final hz = math.max(_hw(TubeMeasure.diameter), _hw(TubeMeasure.width));
    final hzColor = Color.lerp(_color(TubeMeasure.diameter), _color(TubeMeasure.width), m)!;
    final hzStroke = 1.3 + 1.1 * hz;
    _extension(canvas, Offset(left, bottom - 2), Offset(left, wy + 4), hzColor);
    _extension(canvas, Offset(right, bottom - 2), Offset(right, wy + 4), hzColor);
    _arrows(canvas, Offset(left, wy), Offset(right, wy), hzColor, hzStroke);
    if (m < 1) {
      _text(
        canvas,
        diameter.isEmpty ? 'Ø' : 'Ø $diameter',
        Offset(c.dx, wy + 5),
        _color(TubeMeasure.diameter, 1 - m),
        TubeMeasure.diameter,
        center: true,
        caption: 'diâmetro externo',
      );
    }
    if (m > 0) {
      final label = rectangular ? (width.isEmpty ? 'A' : 'A $width') : (width.isEmpty ? 'L' : 'L $width');
      _text(
        canvas,
        label,
        Offset(c.dx, wy + 5),
        _color(TubeMeasure.width, m),
        TubeMeasure.width,
        center: true,
        caption: rectangular ? 'lado A (por fora)' : 'largura (lado maior)',
      );
    }

    // The height of the oblong tube: a vertical line on the right, fading in as the section flattens.
    if (m > 0.02) {
      final hx = right + 17;
      final hc = _color(TubeMeasure.height, m);
      _extension(canvas, Offset(right - 2, top), Offset(hx + 4, top), hc);
      _extension(canvas, Offset(right - 2, bottom), Offset(hx + 4, bottom), hc);
      _arrows(canvas, Offset(hx, top), Offset(hx, bottom), hc, _stroke(TubeMeasure.height));
      final label = rectangular ? (height.isEmpty ? 'B' : 'B $height') : (height.isEmpty ? 'A' : 'A $height');
      _text(canvas, label, Offset(hx + 8, c.dy - 13), hc, TubeMeasure.height, caption: rectangular ? 'lado B (por fora)' : 'altura (lado menor)');
    }

    // The wall: a leader from the wall to a label; its place follows the shape.
    const a = -math.pi / 4;
    final rMid = (w / 2 + (w / 2 - td)) / 2;
    final roundPoint = Offset(c.dx + rMid * math.cos(a), c.dy + rMid * math.sin(a));
    final oblongPoint = Offset(c.dx + w / 4, top + td / 2);
    final wallPoint = Offset.lerp(roundPoint, oblongPoint, m)!;
    final labelAt = Offset.lerp(Offset(c.dx + w / 2 + 36, c.dy - h / 2 + 2), Offset(right + 17 - 22, top - 38), m)!;
    final tc = _color(TubeMeasure.thickness);
    canvas.drawLine(
      labelAt + const Offset(-4, 9),
      wallPoint,
      Paint()
        ..color = tc
        ..strokeWidth = _stroke(TubeMeasure.thickness)
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(wallPoint, 2.8, Paint()..color = tc);
    _text(canvas, thickness.isEmpty ? 'e' : 'e $thickness', labelAt, tc, TubeMeasure.thickness, caption: 'espessura da parede');
  }

  void _sideView(Canvas canvas) {
    // The tube lying down, with the length under it.
    const x0 = 24.0, x1 = 276.0, top = 158.0, h = 16.0;
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
    const ly = top + h + 13;
    final lc = _color(TubeMeasure.length);
    _extension(canvas, const Offset(x0, top + h + 2), const Offset(x0, ly + 4), lc);
    _extension(canvas, const Offset(x1, top + h + 2), const Offset(x1, ly + 4), lc);
    _arrows(canvas, const Offset(x0, ly), const Offset(x1, ly), lc, _stroke(TubeMeasure.length));
    _text(canvas, length.isEmpty ? 'C' : 'C $length', const Offset((x0 + x1) / 2, ly + 4), lc, TubeMeasure.length, center: true, caption: 'comprimento');
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
    final main = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.lerp(FontWeight.w700, FontWeight.w800, _hw(m))),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cap = TextPainter(
      text: TextSpan(
        text: caption,
        style: TextStyle(color: color.withValues(alpha: color.a * 0.9), fontSize: 10.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = math.max(main.width, cap.width);
    var x = center ? at.dx - w / 2 : at.dx;
    // Keep the label on the sheet, never cut at an edge.
    x = x.clamp(1.0, TubeDiagram.size.width - w - 1);
    main.paint(canvas, Offset(x + (center ? (w - main.width) / 2 : 0), at.dy));
    cap.paint(canvas, Offset(x + (center ? (w - cap.width) / 2 : 0), at.dy + main.height - 1));
  }

  @override
  bool shouldRepaint(_TubePainter old) =>
      old.geo != geo ||
      old.rectangular != rectangular ||
      old.diameter != diameter ||
      old.width != width ||
      old.height != height ||
      old.thickness != thickness ||
      old.length != length ||
      old.highlight != highlight ||
      old.previous != previous ||
      old.focusT != focusT ||
      old.ink != ink ||
      old.accent != accent ||
      old.steel != steel;
}
