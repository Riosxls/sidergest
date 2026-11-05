import 'package:ebt_engenharia/screens/price_simulator.dart';
import 'package:ebt_engenharia/widgets/tube_diagram.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'price_simulator_test.dart' show Rig, pumpApp, sessionFor, suggestion;

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

  group('oblong tube', () {
    Future<void> pickOblong(WidgetTester tester) async {
      await tester.tap(find.text('Oblongo'));
      await tester.pumpAndSettle();
    }

    testWidgets('the oblong drawing names its sides', (tester) async {
      await pumpApp(tester, const SizedBox(width: 320, child: TubeDiagram(profile: TubeProfile.oblong, width: '17', height: '6,2', thickness: '1,4', length: '680')), size: const Size(500, 500));
      expect(find.bySemanticsLabel('Desenho do tubo oblongo: largura 17 mm, altura 6,2 mm, espessura 1,4 mm, comprimento 680 mm'), findsOneWidget);
    });

    testWidgets('asks for width and height, sends shape=oblong, and prices the round tube of the same perimeter', (tester) async {
      final rig = Rig()
        ..data = {
          ...suggestion(),
          'weight': {'netKg': 0.2741, 'grossKg': 0.2818, 'lossPercent': 2.8},
          'profile': {'shape': 'Oblong', 'equivalentDiameter': 13.08},
        };
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
      await pickOblong(tester);
      expect(find.byKey(const ValueKey('price-sim-diameter')), findsNothing);
      expect(find.byKey(const ValueKey('price-sim-width')), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-height')), findsOneWidget);
      expect(diagram(tester).profile, TubeProfile.oblong);

      await tester.enterText(find.byKey(const ValueKey('price-sim-width')), '17');
      await tester.enterText(find.byKey(const ValueKey('price-sim-height')), '6,2');
      await tester.enterText(find.byKey(const ValueKey('price-sim-thickness')), '1,4');
      await tester.enterText(find.byKey(const ValueKey('price-sim-length')), '680');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final q = rig.suggestions.last.url.queryParameters;
      expect(q['shape'], 'oblong');
      expect(q['width'], '17');
      expect(q['height'], '6.2');
      expect(q['thickness'], '1.4');
      expect(q['length'], '680');
      expect(q.containsKey('diameter'), isFalse);
      expect(find.byKey(const ValueKey('price-sim-oblong-note')), findsOneWidget);
      expect(find.textContaining('Ø 13,08'), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-markup')), findsOneWidget);
    });

    testWidgets('the shape markup raises the suggestion, and is not used for a round tube', (tester) async {
      final rig = Rig()..data = {...suggestion(), 'profile': {'shape': 'Oblong', 'equivalentDiameter': 13.08}};
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
      await pickOblong(tester);
      for (final e in {'price-sim-width': '17', 'price-sim-height': '6,2', 'price-sim-thickness': '1,4', 'price-sim-length': '680'}.entries) {
        await tester.enterText(find.byKey(ValueKey(e.key)), e.value);
      }
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.textContaining('R\$ 20,25/kg'), findsWidgets); // 20,25 + 0%
      await tester.enterText(find.byKey(const ValueKey('price-sim-markup')), '10');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('price-sim-suggestion'))).data, contains('R\$ 22,28/kg')); // 20,25 + 10%
      expect(tester.widget<Text>(find.byKey(const ValueKey('price-sim-suggestion'))).data, contains('R\$ 6,18/peça')); // 5,62 + 10%
      expect(find.textContaining('Já inclui o acréscimo de 10%'), findsOneWidget);
      // back to round: the markup no longer applies
      await tester.tap(find.text('Redondo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-sim-markup')), findsNothing);
    });

    testWidgets('width smaller than height and a wall too thick are said in Portuguese', (tester) async {
      final rig = Rig();
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
      await pickOblong(tester);
      await tester.enterText(find.byKey(const ValueKey('price-sim-width')), '5');
      await tester.enterText(find.byKey(const ValueKey('price-sim-height')), '6');
      await tester.enterText(find.byKey(const ValueKey('price-sim-thickness')), '3');
      await tester.enterText(find.byKey(const ValueKey('price-sim-length')), '680');
      await tester.pumpAndSettle();
      expect(find.text('A largura é o lado maior: não pode ser menor que a altura.'), findsOneWidget);
      expect(find.text('A espessura é grande demais: 2 × espessura precisa ser menor que a altura.'), findsOneWidget);
      expect(rig.suggestions, isEmpty);
    });
  });
}
