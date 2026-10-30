import 'dart:math' as math;

import 'package:ebt_engenharia/main.dart';
import 'package:ebt_engenharia/widgets/pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double ratio(Color a, Color b) {
  final (hi, lo) = (_lum(a), _lum(b)).$1 >= _lum(b) ? (_lum(a), _lum(b)) : (_lum(b), _lum(a));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    final cs = appTheme(brightness).colorScheme;
    group('${brightness.name} theme text on the surfaces it is drawn on', () {
      test('field labels (onSurfaceVariant) on cards stay readable', () {
        expect(ratio(cs.onSurfaceVariant, cs.surfaceContainerHigh), greaterThanOrEqualTo(4.5));
      });

      test('upcoming stage-path steps stay readable', () {
        expect(ratio(cs.onSurfaceVariant, cs.surfaceContainerHighest), greaterThanOrEqualTo(4.5));
      });

      test('text on the active step (onPrimary on primary)', () {
        expect(ratio(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5));
      });

      test('error outline and label on the status card are readable', () {
        expect(ratio(cs.error, cs.surfaceContainerHigh), greaterThanOrEqualTo(3.0));
      });
    });
  }

  test('white text on the done (green) and failed (red) steps is readable', () {
    expect(ratio(Colors.white, const Color(0xFF23803F)), greaterThanOrEqualTo(4.5));
    expect(ratio(Colors.white, const Color(0xFFC62828)), greaterThanOrEqualTo(4.5));
  });

  testWidgets('status card tones keep their text readable', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(MaterialApp(theme: appTheme(b), home: Builder(builder: (c) => Text('x', key: ValueKey(b.name)))));
      final context = tester.element(find.byKey(ValueKey(b.name)));
      for (final tone in Tone.values) {
        final (bg, fg) = toneColors(context, tone);
        expect(ratio(fg, bg), greaterThanOrEqualTo(4.5), reason: '${b.name} ${tone.name}');
      }
    }
  });
}
