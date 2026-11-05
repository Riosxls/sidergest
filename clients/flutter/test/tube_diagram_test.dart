import 'package:ebt_engenharia/screens/price_simulator.dart';
import 'package:ebt_engenharia/widgets/tube_diagram.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'price_simulator_test.dart' show Rig, pumpApp, sessionFor;

TubeDiagram diagram(WidgetTester tester) => tester.widget<TubeDiagram>(find.byType(TubeDiagram));

void main() {
  testWidgets('the drawing says what it shows, with the typed values or a placeholder', (tester) async {
    await pumpApp(tester, const SizedBox(width: 320, child: TubeDiagram(diameter: '9,5', thickness: '2,05', length: '3000')), size: const Size(500, 500));
    expect(find.bySemanticsLabel('Desenho do tubo: diâmetro externo 9,5 mm, espessura 2,05 mm, comprimento 3000 mm'), findsOneWidget);
    await pumpApp(tester, const SizedBox(width: 320, child: TubeDiagram()), size: const Size(500, 500));
    expect(find.bySemanticsLabel('Desenho do tubo: diâmetro externo não informado, espessura não informada, comprimento não informado'), findsOneWidget);
  });

  testWidgets('the simulator draws the tube beside the fields and highlights the measure being edited', (tester) async {
    final rig = Rig();
    await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
    expect(find.byKey(const ValueKey('tube-diagram')), findsOneWidget);
    // beside the fields on a wide window
    expect(tester.getTopLeft(find.byKey(const ValueKey('tube-diagram'))).dx, greaterThan(tester.getTopLeft(find.byKey(const ValueKey('price-sim-diameter'))).dx));
    expect(diagram(tester).highlight, TubeMeasure.diameter); // the diameter field starts focused

    await tester.enterText(find.byKey(const ValueKey('price-sim-thickness')), '1,4');
    await tester.pump();
    expect(diagram(tester).highlight, TubeMeasure.thickness);
    expect(diagram(tester).thickness, '1,4');

    await tester.tap(find.byKey(const ValueKey('price-sim-length')));
    await tester.pump();
    expect(diagram(tester).highlight, TubeMeasure.length);
    await tester.enterText(find.byKey(const ValueKey('price-sim-length')), '680');
    await tester.pump();
    expect(diagram(tester).length, '680');
  });

  testWidgets('on a phone the drawing comes first and the fields stay usable', (tester) async {
    final rig = Rig();
    await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')), size: const Size(380, 1400));
    expect(find.byKey(const ValueKey('tube-diagram')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('tube-diagram'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('price-sim-diameter'))).dy));
    expect(tester.takeException(), isNull);
  });
}
