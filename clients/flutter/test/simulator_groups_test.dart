import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:ebt_engenharia/reports/print_docs.dart';
import 'package:ebt_engenharia/screens/price_simulator.dart';
import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:ebt_engenharia/widgets/price_trend_chart.dart';
import 'package:ebt_engenharia/widgets/tube_diagram.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'price_simulator_test.dart' show Rig, pumpApp, sessionFor, suggestion, typeDims;
import 'sales_more_support.dart';

/// [suggestion] with the fields of the new server answer replaced.
Map<String, dynamic> withExtras({Map<String, dynamic>? suggestionFields, Map<String, dynamic>? top}) {
  final base = suggestion();
  return {
    ...base,
    'suggestion': {...(base['suggestion'] as Map<String, dynamic>), ...?suggestionFields},
    ...?top,
  };
}

/// Opens the simulator dialog from a button. With [settle] false the request of the first measures is left in flight.
Future<List<String>> openSim(
  WidgetTester tester,
  Rig rig, {
  num? diameter = 25.4,
  num? width,
  num? height,
  TubeProfile profile = TubeProfile.round,
  int? productId,
  String? spec,
  ({int id, String name})? customer,
  bool unitIsKg = false,
  bool settle = true,
}) async {
  final used = <String>[];
  final session = sessionFor(rig, 'Sales');
  await tester.pumpWidget(const SizedBox()); // a fresh tree: a screen pumped twice in one test would keep its old state
  await pumpApp(
    tester,
    Builder(
      builder: (c) => TextButton(
        key: const ValueKey('open'),
        onPressed: () => showPriceSimulator(
          c,
          session,
          diameter: diameter,
          width: width,
          height: height,
          profile: profile,
          productId: productId,
          thickness: 1.5,
          length: 3000,
          spec: spec,
          customer: customer,
          unitIsKg: unitIsKg,
          onUse: used.add,
        ),
        child: const Text('abrir'),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  if (settle) {
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }
  return used;
}

Future<void> typeKeys(WidgetTester tester, Map<String, String> values) async {
  for (final e in values.entries) {
    await tester.enterText(find.byKey(ValueKey(e.key)), e.value);
  }
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

Future<Rig> screenWith(WidgetTester tester, Map<String, dynamic> data, {String role = 'Sales', Size size = const Size(1400, 2400)}) async {
  final rig = Rig()..data = data;
  await tester.pumpWidget(const SizedBox()); // a fresh tree: a screen pumped twice in one test would keep its old state
  await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, role)), size: size);
  await typeDims(tester);
  return rig;
}

TubeDiagram diagram(WidgetTester tester) => tester.widget<TubeDiagram>(find.byType(TubeDiagram));

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  setUp(() => priceSimulatorNow = () => DateTime(2026, 11, 5));
  tearDown(() => priceSimulatorNow = DateTime.now);

  group('A1: a result only ever belongs to the current inputs', () {
    testWidgets('an answer that arrives late for old measures is never shown and never feeds "Usar este preço"', (tester) async {
      final rig = Rig();
      final slow = Completer<void>(), second = Completer<void>();
      rig.holds.addAll([slow, second]);
      await openSim(tester, rig, settle: false); // the request for 3000 mm goes out and is held
      expect(rig.suggestions.length, 1);
      expect(find.textContaining('Sugestão:'), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('price-sim-use'))).onPressed, isNull);

      // The length changes while the first answer is still on its way; the new answer will be different.
      rig.data = withExtras(
        top: {
          'weight': {'netKg': 1.0, 'grossKg': 1.1, 'lossPercent': 2.8},
        },
        suggestionFields: {'pricePerPiece': 7.77},
      );
      await tester.enterText(find.byKey(const ValueKey('price-sim-length')), '3500');
      await tester.pump();
      slow.complete(); // the old answer arrives now
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Sugestão:'), findsNothing, reason: 'the answer of the old measures must not render');
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('price-sim-use'))).onPressed, isNull);

      await tester.pump(const Duration(milliseconds: 450)); // the quiet moment passes: the request for 3500 mm goes out, held
      expect(rig.suggestions.length, 2);
      expect(find.textContaining('Sugestão:'), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('price-sim-use'))).onPressed, isNull);

      second.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('R\$ 7,77/peça'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('price-sim-use'))).onPressed, isNotNull);
    });

    testWidgets('the old result disappears the moment a field changes, before the new request goes out', (tester) async {
      final rig = Rig();
      await openSim(tester, rig);
      expect(find.textContaining('Sugestão:'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('price-sim-thickness')), '1,6');
      await tester.pump();
      expect(find.textContaining('Sugestão:'), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('price-sim-use'))).onPressed, isNull);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sugestão:'), findsOneWidget);
    });
  });

  group('A2, A3, A6: reason, count of sales, product', () {
    testWidgets('the number of sales is the one the server used, with the month of the newest and the oldest', (tester) async {
      final rig = Rig()..data = withExtras(suggestionFields: {'usedCount': 1, 'newestDate': '2026-09-10', 'oldestDate': '2026-09-10'});
      await openSim(tester, rig);
      expect(find.text('Baseado em 1 venda parecida, a mais recente é de set/2026 (venda de 2 meses atrás)'), findsOneWidget);
    });

    testWidgets('the repeat sale is named from `repeat`, not from the last price line', (tester) async {
      final rig = Rig()
        ..data = withExtras(
          suggestionFields: {'basis': 'CustomerRepeat'},
          top: {
            'repeat': {
              'date': '2026-02-03',
              'customer': 'Zeta Aços',
              'diameter': 25.4,
              'thickness': 1.5,
              'length': 3000,
              'unit': 'KG',
              'unitPrice': 21.5,
              'pricePerKg': 21.5,
            },
          },
        );
      await openSim(tester, rig, customer: (id: 2, name: 'BTS Tubos'));
      expect(find.text('Mesmo preço cobrado de Zeta Aços em 03/02/2026 (R\$ 21,50/kg) para esta medida (venda de 9 meses atrás)'), findsOneWidget);
    });

    testWidgets('the product is sent when the simulator was opened from a line with a product, and left out otherwise', (tester) async {
      final rig = Rig();
      await openSim(tester, rig, productId: 7);
      expect(rig.suggestions.last.url.queryParameters['productId'], '7');
      final other = Rig();
      await openSim(tester, other);
      expect(other.suggestions.last.url.queryParameters.containsKey('productId'), isFalse);
    });
  });

  group('A7: import result', () {
    test('the reasons become one short list, zeros left out', () {
      // exercised through the dialog in price_simulator_test; here the empty cases
      expect(PriceSimulatorPanel.debounce, const Duration(milliseconds: 400));
    });

    testWidgets('no reasons from the server: no list, "Atualizadas" still shown', (tester) async {
      final rig = Rig()..importResult = {'read': 10, 'imported': 5, 'duplicates': 0, 'skipped': 0, 'firstDate': '2020-01-01', 'lastDate': '2020-02-01'};
      final old = priceHistoryFilePicker;
      priceHistoryFilePicker = () async => (name: 'v.csv', bytes: Uint8List(0));
      addTearDown(() => priceHistoryFilePicker = old);
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'SalesManager')));
      await tester.tap(find.byKey(const ValueKey('price-sim-import')));
      await tester.pumpAndSettle();
      expect(find.text('Atualizadas: 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-skipped-reasons')), findsNothing);
    });
  });

  group('A-minor', () {
    test('the drawing reads numbers like the form does', () {
      expect(TubeDiagram.parseMeasure('1.500'), 1500);
      expect(TubeDiagram.parseMeasure('1,5'), 1.5);
      expect(TubeDiagram.parseMeasure('25.4'), 25.4);
      expect(TubeDiagram.parseMeasure(' 3.000,5 '), 3000.5);
      expect(TubeDiagram.parseMeasure('abc'), isNull);
    });

    testWidgets('the result area is a live region', (tester) async {
      await screenWith(tester, suggestion());
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true), findsWidgets);
    });

    testWidgets('similar sales of the customer and of the specification say so in words, and names match without case or accents', (tester) async {
      final rig = Rig();
      await openSim(tester, rig, customer: (id: 2, name: 'ZÉTA'), spec: 'NBR');
      expect(find.text('Combina'), findsOneWidget);
      expect(find.text('● mesmo cliente · mesma espec.'), findsOneWidget); // Zeta, NBR
      expect(find.textContaining('mesmo cliente'), findsOneWidget);
    });

    testWidgets('the oblong note says where the markup goes without saying "ao lado"', (tester) async {
      final rig = Rig()
        ..data = withExtras(
          top: {
            'profile': {'shape': 'Oblong', 'equivalentDiameter': 13.08},
          },
        );
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
      await tester.tap(find.text('Oblongo'));
      await tester.pumpAndSettle();
      await typeKeys(tester, {'price-sim-width': '17', 'price-sim-height': '6,2', 'price-sim-thickness': '1,4', 'price-sim-length': '680'});
      expect(find.textContaining('no campo de acréscimo'), findsOneWidget);
      expect(find.textContaining('ao lado'), findsNothing);
    });
  });

  group('B1: weak basis', () {
    testWidgets('few sales, and an old newest one, give a warning with the month', (tester) async {
      final rig = Rig()..data = withExtras(suggestionFields: {'usedCount': 2, 'newestDate': '2024-03-10', 'oldestDate': '2023-01-01'});
      await openSim(tester, rig);
      expect(find.text('Baseado em 2 vendas, a mais recente de mar/2024. Confira antes de usar.'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.textContaining('vendas de 32 a 46 meses atrás'), findsOneWidget); // the age is always in the reason line
    });

    testWidgets('three recent sales are not warned about', (tester) async {
      final rig = Rig()..data = withExtras(suggestionFields: {'usedCount': 3});
      await openSim(tester, rig);
      expect(find.byKey(const ValueKey('price-sim-weak')), findsNothing);
    });

    testWidgets('enough recent sales but the most similar one is old', (tester) async {
      final data = withExtras(suggestionFields: {'usedCount': 6, 'newestDate': '2026-10-01'});
      ((data['similar'] as List)[1] as Map)['date'] = '2024-05-05'; // distance 0.5, the nearest
      final rig = Rig()..data = data;
      await openSim(tester, rig);
      expect(find.text('A venda mais parecida é de mai/2024. Confira antes de usar.'), findsOneWidget);
    });

    testWidgets('an old repeat price of the customer is warned about', (tester) async {
      final rig = Rig()
        ..data = withExtras(
          suggestionFields: {'basis': 'CustomerRepeat', 'usedCount': 1},
          top: {
            'repeat': {'date': '2025-01-10', 'customer': 'BTS Tubos', 'unit': 'KG', 'unitPrice': 20.0, 'pricePerKg': 20.0},
          },
        );
      await openSim(tester, rig, customer: (id: 2, name: 'BTS Tubos'));
      expect(find.textContaining('é de jan/2025. Confira antes de usar.'), findsOneWidget);
    });
  });

  group('C1, C2: what this customer paid', () {
    final history = [
      {'date': '2026-09-01', 'unit': 'KG', 'unitPrice': 21.0, 'pricePerKg': 21.0, 'quantity': 500},
      {'date': '2026-05-01', 'unit': 'KG', 'unitPrice': 20.0, 'pricePerKg': 20.0, 'quantity': null},
      {'date': '2026-01-01', 'unit': 'KG', 'unitPrice': 20.0, 'pricePerKg': 20.0, 'quantity': 300},
    ];

    testWidgets('lists the last sales with the change against the previous one', (tester) async {
      await screenWith(
        tester,
        withExtras(
          top: {
            'customerHistory': history,
            'customerTrend': [
              {'month': '2026-01', 'pricePerKg': 20.0, 'count': 1},
              {'month': '2026-09', 'pricePerKg': 21.0, 'count': 1},
            ],
          },
        ),
      );
      expect(find.text('Este cliente pagou'), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-customer-history')), findsOneWidget);
      expect(find.text('+5%'), findsOneWidget);
      expect(find.text('igual'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.byKey(const ValueKey('price-sim-customer-trend')), findsOneWidget); // two months are enough for his own chart
    });

    testWidgets('a price that fell shows the minus, and an empty history hides the block', (tester) async {
      await screenWith(
        tester,
        withExtras(
          top: {
            'customerHistory': [
              {'date': '2026-09-01', 'unit': 'KG', 'unitPrice': 18.0, 'pricePerKg': 18.0, 'quantity': 1},
              {'date': '2026-05-01', 'unit': 'KG', 'unitPrice': 20.0, 'pricePerKg': 20.0, 'quantity': 1},
            ],
          },
        ),
      );
      expect(find.text('-10%'), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-customer-trend')), findsNothing); // no trend sent
      await screenWith(tester, suggestion());
      expect(find.text('Este cliente pagou'), findsNothing);
    });

    testWidgets('the customer factor is informational, shown from 3 sales, and does not move the suggestion', (tester) async {
      await screenWith(
        tester,
        withExtras(
          top: {
            'customerFactor': {'ratio': 0.92, 'sampleSize': 6},
          },
        ),
      );
      expect(
        textOf(tester, 'price-sim-factor'),
        'Este cliente costuma pagar 8% abaixo de tubos parecidos (6 vendas). É só uma informação: não entra na sugestão.',
      );
      expect(find.text('Sugestão: R\$ 20,25/kg  ·  R\$ 5,62/peça'), findsOneWidget);
      await screenWith(
        tester,
        withExtras(
          top: {
            'customerFactor': {'ratio': 1.1, 'sampleSize': 6},
          },
        ),
      );
      expect(find.textContaining('10% acima de tubos parecidos'), findsOneWidget);
      await screenWith(
        tester,
        withExtras(
          top: {
            'customerFactor': {'ratio': 0.92, 'sampleSize': 2},
          },
        ),
      );
      expect(find.byKey(const ValueKey('price-sim-factor')), findsNothing);
    });
  });

  group('C3: price by specification', () {
    final bySpec = [
      {'spec': 'NBR', 'count': 12, 'medianPerKg': 18.0, 'nearestDistance': 0.4},
      {'spec': 'NBK', 'count': 3, 'medianPerKg': 22.0, 'nearestDistance': 1.0},
      {'spec': 'EN10305', 'count': 1, 'medianPerKg': 27.0, 'nearestDistance': 2.0},
    ];

    testWidgets('shows each class with its median and the spread, only while no specification is chosen', (tester) async {
      final rig = await screenWith(tester, withExtras(top: {'bySpec': bySpec}));
      expect(find.byKey(const ValueKey('price-sim-by-spec')), findsOneWidget);
      expect(find.text('NBR 5599'), findsWidgets);
      expect(find.text('12 vendas'), findsOneWidget);
      expect(find.text('1 venda'), findsOneWidget);
      expect(find.text('R\$ 22,00'), findsOneWidget);
      expect(find.textContaining('A especificação muda o preço em até 50%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('price-sim-spec')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NBR 5599').last);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(rig.suggestions.last.url.queryParameters['spec'], 'NBR');
      expect(find.byKey(const ValueKey('price-sim-by-spec')), findsNothing);
    });

    testWidgets('a single class is not worth a table', (tester) async {
      await screenWith(
        tester,
        withExtras(
          top: {
            'bySpec': [bySpec.first],
          },
        ),
      );
      expect(find.byKey(const ValueKey('price-sim-by-spec')), findsNothing);
    });
  });

  group('C4: margin over the cost', () {
    testWidgets('is computed on the price per kg; low or negative margins are in the warning tone; the cost is never sent', (tester) async {
      final rig = await screenWith(tester, suggestion());
      expect(find.byKey(const ValueKey('price-sim-margin')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('price-sim-cost')), '16');
      await tester.pumpAndSettle();
      expect(textOf(tester, 'price-sim-margin'), 'Margem sobre o custo: 21% (R\$ 4,25/kg)');
      final normal = tester.widget<Text>(find.byKey(const ValueKey('price-sim-margin'))).style!.color;
      await tester.enterText(find.byKey(const ValueKey('price-sim-cost')), '19');
      await tester.pumpAndSettle();
      expect(textOf(tester, 'price-sim-margin'), 'Margem sobre o custo: 6% (R\$ 1,25/kg)');
      expect(tester.widget<Text>(find.byKey(const ValueKey('price-sim-margin'))).style!.color, isNot(normal)); // below 10%: the warning tone
      await tester.enterText(find.byKey(const ValueKey('price-sim-cost')), '22');
      await tester.pumpAndSettle();
      expect(textOf(tester, 'price-sim-margin'), 'Margem sobre o custo: -9% (R\$ -1,75/kg)');
      expect(rig.suggestions.length, 1, reason: 'typing a cost asks nothing of the server');
      expect(rig.suggestions.last.url.queryParameters.keys.any((k) => k.toLowerCase().contains('cost')), isFalse);
    });

    testWidgets('uses the price with the shape markup', (tester) async {
      final rig = Rig()
        ..data = withExtras(
          top: {
            'profile': {'shape': 'Rectangular', 'equivalentDiameter': 20.0},
          },
        );
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')), size: const Size(1400, 2400));
      await tester.tap(find.text('Retangular'));
      await tester.pumpAndSettle();
      await typeKeys(tester, {
        'price-sim-side-a': '40',
        'price-sim-side-b': '20',
        'price-sim-thickness': '1,5',
        'price-sim-length': '3000',
        'price-sim-markup': '10',
        'price-sim-cost': '16',
      });
      expect(textOf(tester, 'price-sim-margin'), 'Margem sobre o custo: 28% (R\$ 6,28/kg)'); // 22,28 with +10%
    });
  });

  group('C5: copy and print', () {
    testWidgets('"Copiar resumo" puts the numbers on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await screenWith(tester, suggestion());
      await tester.enterText(find.byKey(const ValueKey('price-sim-quantity')), '500');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-sim-print')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('price-sim-copy')));
      await tester.tap(find.byKey(const ValueKey('price-sim-copy')));
      await tester.pumpAndSettle();
      expect(copied, isNotNull);
      expect(copied, contains('Tubo redondo: Ø 25,4 mm, espessura 1,5 mm, comprimento 3000 mm'));
      expect(copied, contains('Quantidade: 500 peças'));
      expect(copied, contains('Peso: líquido 563 g, bruto 578 g'));
      expect(copied, contains('Preço sugerido: R\$ 20,25/kg · R\$ 5,62/peça (faixa R\$ 19,80 a R\$ 21,00/kg)'));
      expect(copied, contains('Total: R\$ 2.810,00'));
      expect(copied, contains('Confiança: Alta'));
      expect(copied, contains('Baseado em 5 vendas parecidas'));
      expect(copied, contains('Simulação de preço de 05/11/2026'));
      expect(find.text('Resumo copiado.'), findsOneWidget);
    });

    TestWidgetsFlutterBinding.ensureInitialized();
    final sheet = <String, dynamic>{
      'date': '2026-11-05',
      'shape': 'Tubo redondo',
      'measures': 'Ø 25,4 mm, espessura 1,5 mm, comprimento 3000 mm',
      'spec': 'NBR 5599',
      'customer': 'BTS Tubos',
      'quantity': 500,
      'netKg': 0.5625,
      'grossKg': 0.5782,
      'lossPercent': 2.8,
      'pricePerKg': 20.25,
      'pricePerPiece': 5.62,
      'low': 19.8,
      'high': 21.0,
      'total': 2810,
      'confidence': 'Alta',
      'reason': 'Baseado em 5 vendas parecidas',
      'warning': 'Baseado em 2 vendas, a mais recente de mar/2024. Confira antes de usar.',
      'markupPercent': 10,
      'costPerKg': 16,
      'margin': 'Margem sobre o custo: 21% (R\$ 4,25/kg)',
      'note': 'para a BTS',
      'similar': suggestion()['similar'],
    };

    test('the one-page A4 sheet builds', () async {
      final bytes = await buildSimulationPdf(sessionFor(Rig(), 'Sales').api, sheet);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(1500));
    });

    test('the sheet builds with nothing optional and with many similar sales', () async {
      final api = sessionFor(Rig(), 'Sales').api;
      final bare = await buildSimulationPdf(api, {'shape': 'Tubo redondo', 'measures': 'x', 'similar': const []});
      expect(String.fromCharCodes(bare.take(4)), '%PDF');
      final many = await buildSimulationPdf(api, {...sheet, 'similar': List.generate(40, (i) => (suggestion()['similar'] as List).first)});
      expect(String.fromCharCodes(many.take(4)), '%PDF');
    });
  });

  group('C6: rectangular tube', () {
    Future<Rig> pickRect(WidgetTester tester, {Map<String, dynamic>? data}) async {
      final rig = Rig()
        ..data =
            data ??
            withExtras(
              top: {
                'weight': {'netKg': 0.9, 'grossKg': 0.92, 'lossPercent': 2.8},
                'profile': {'shape': 'Rectangular', 'equivalentDiameter': 19.1},
              },
            );
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')), size: const Size(1400, 2400));
      await tester.tap(find.text('Retangular'));
      await tester.pumpAndSettle();
      return rig;
    }

    testWidgets('asks for the two sides, says square is equal sides, and sends shape=rect', (tester) async {
      final rig = await pickRect(tester);
      expect(find.byKey(const ValueKey('price-sim-diameter')), findsNothing);
      expect(find.text('Lado A (mm)'), findsOneWidget);
      expect(find.text('Lado B (mm)'), findsOneWidget);
      expect(find.textContaining('Quadrado: use lados iguais'), findsOneWidget);
      expect(find.text('Digite os lados A e B, a espessura e o comprimento para ver o peso e o preço sugerido.'), findsOneWidget);
      expect(diagram(tester).profile, TubeProfile.rectangular);
      await typeKeys(tester, {'price-sim-side-a': '40', 'price-sim-side-b': '20', 'price-sim-thickness': '1,5', 'price-sim-length': '3000'});
      final q = rig.suggestions.last.url.queryParameters;
      expect(q['shape'], 'rect');
      expect(q['width'], '40');
      expect(q['height'], '20');
      expect(q['thickness'], '1.5');
      expect(q.containsKey('diameter'), isFalse);
      expect(find.textContaining('Ø 19,1 mm'), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-markup')), findsOneWidget);
      expect(find.text('Acréscimo (%)'), findsOneWidget);
    });

    testWidgets('the sides may be typed in either order', (tester) async {
      final rig = await pickRect(tester);
      await typeKeys(tester, {'price-sim-side-a': '20', 'price-sim-side-b': '40', 'price-sim-thickness': '1,5', 'price-sim-length': '3000'});
      expect(rig.suggestions.last.url.queryParameters['width'], '20');
      expect(rig.suggestions.last.url.queryParameters['height'], '40');
    });

    testWidgets('a wall too thick for the shorter side is said in Portuguese', (tester) async {
      final rig = await pickRect(tester);
      await typeKeys(tester, {'price-sim-side-a': '40', 'price-sim-side-b': '20', 'price-sim-thickness': '10', 'price-sim-length': '3000'});
      expect(find.text('A espessura é grande demais: 2 × espessura precisa ser menor que o menor lado.'), findsOneWidget);
      expect(rig.suggestions, isEmpty);
    });

    testWidgets('the markup applies to the rectangular tube too', (tester) async {
      await pickRect(tester);
      await typeKeys(tester, {
        'price-sim-side-a': '40',
        'price-sim-side-b': '20',
        'price-sim-thickness': '1,5',
        'price-sim-length': '3000',
        'price-sim-markup': '10',
      });
      expect(tester.widget<Text>(find.byKey(const ValueKey('price-sim-suggestion'))).data, contains('R\$ 22,28/kg'));
      expect(find.textContaining('Já inclui o acréscimo de 10%'), findsOneWidget);
    });

    testWidgets('the drawing names its sides', (tester) async {
      await pumpApp(
        tester,
        const SizedBox(
          width: 320,
          child: TubeDiagram(profile: TubeProfile.rectangular, width: '40', height: '20', thickness: '1,5', length: '3000'),
        ),
        size: const Size(500, 500),
      );
      expect(find.bySemanticsLabel('Desenho do tubo retangular: lado A 40 mm, lado B 20 mm, espessura 1,5 mm, comprimento 3000 mm'), findsOneWidget);
    });

    testWidgets('the section morphs from round to rectangular, and does not animate when the system turns animations off', (tester) async {
      await pumpApp(
        tester,
        const SizedBox(
          width: 400,
          child: TubeDiagram(diameter: '9,5', thickness: '1'),
        ),
        size: const Size(500, 500),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TubeDiagram(profile: TubeProfile.rectangular, width: '40', height: '20', thickness: '1,4'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TubeDiagram(profile: TubeProfile.rectangular, width: '30', height: '30', thickness: '1,4'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.hasRunningAnimations, isTrue); // a square: the proportions glide
      await tester.pumpAndSettle();

      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TubeDiagram(diameter: '9,5', thickness: '1'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TubeDiagram(profile: TubeProfile.rectangular, width: '40', height: '20', thickness: '1,4'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    for (final width in [1300.0, 860.0, 520.0, 380.0]) {
      testWidgets('no overflow at ${width.toInt()} px with the rectangular form', (tester) async {
        final rig = Rig();
        await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')), size: Size(width, 1600));
        await tester.tap(find.text('Retangular'));
        await tester.pumpAndSettle();
        await typeKeys(tester, {'price-sim-side-a': '40', 'price-sim-side-b': '20', 'price-sim-thickness': '1,5', 'price-sim-length': '3000'});
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an existing rectangular simulator keeps the round fields when going back to round', (tester) async {
      final rig = await pickRect(tester);
      await tester.tap(find.text('Redondo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-sim-diameter')), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-markup')), findsNothing);
      expect(rig.suggestions, isEmpty);
    });
  });

  group('C7: price chart', () {
    final trend = [
      {'month': '2024-11', 'pricePerKg': 19.0, 'count': 3},
      {'month': '2025-05', 'pricePerKg': 20.0, 'count': 2},
      {'month': '2025-11', 'pricePerKg': 21.5, 'count': 4},
      {'month': '2026-05', 'pricePerKg': 22.0, 'count': 1},
      {'month': '2026-11', 'pricePerKg': 23.0, 'count': 5},
    ];

    test('the summary says the movement in words', () {
      expect(trendSummary(TrendPoint.parse(trend)), 'sobe de R\$ 19 para R\$ 23 em 24 meses');
      expect(trendSummary(TrendPoint.parse(trend.reversed.toList())), 'sobe de R\$ 19 para R\$ 23 em 24 meses'); // sorted by month
      expect(trendSummary(const [TrendPoint('2025-01', 23, 1), TrendPoint('2026-01', 19, 1)]), 'cai de R\$ 23 para R\$ 19 em 12 meses');
      expect(trendSummary(const [TrendPoint('2026-01', 20, 1), TrendPoint('2026-07', 20.1, 1)]), 'fica estável em R\$ 20,10 em 6 meses');
      expect(trendSummary(const [TrendPoint('2026-01', 19.4, 1), TrendPoint('2026-02', 19.8, 1)]), 'sobe de R\$ 19,40 para R\$ 19,80 em 1 mês');
      expect(trendSummary(const [TrendPoint('2026-01', 19.4, 1)]), '');
    });

    test('rows that are not understood are left out', () {
      final pts = TrendPoint.parse([
        {'month': '2026-02', 'pricePerKg': 20.0, 'count': 2},
        {'month': 'x', 'pricePerKg': null},
        'lixo',
        {'month': '2026-01', 'pricePerKg': 19, 'count': 1},
      ]);
      expect(pts.map((p) => p.month), ['2026-01', '2026-02']);
      expect(pts.first.long, 'jan/2026');
      expect(pts.first.short, 'jan/26');
    });

    testWidgets('is drawn from the market history, with an accessible summary, and shows month, price and count on hover and on tap', (tester) async {
      await screenWith(
        tester,
        withExtras(
          top: {
            'trend': trend,
            'customerTrend': [
              {'month': '2024-11', 'pricePerKg': 18.0, 'count': 1},
              {'month': '2026-11', 'pricePerKg': 22.0, 'count': 2},
            ],
          },
        ),
        role: 'Sales',
      );
      expect(find.byKey(const ValueKey('price-trend')), findsOneWidget);
      expect(find.text('R\$/kg ao longo do tempo'), findsOneWidget);
      expect(textOf(tester, 'price-trend-summary'), 'Preço por kg sobe de R\$ 19 para R\$ 23 em 24 meses.');
      expect(find.bySemanticsLabel(RegExp('sobe de R\\\$ 19 para R\\\$ 23 em 24 meses')), findsWidgets);
      expect(find.text('Este cliente'), findsWidgets); // legend of the customer's line
      final canvas = find.byKey(const ValueKey('price-trend-canvas'));
      await tester.ensureVisible(canvas);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-trend-tooltip')), findsNothing);
      final topLeft = tester.getTopLeft(canvas);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(topLeft + const Offset(48, 60)); // the left end of the plot: the oldest month
      await tester.pump();
      final tip = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('price-trend-tooltip')), matching: find.byType(Text))).data!;
      expect(tip, contains('nov/2024: R\$ 19,00/kg · 3 vendas'));
      expect(tip, contains('Este cliente: R\$ 18,00/kg · 1 venda')); // he bought that month too
      await mouse.moveTo(Offset.zero);
      await tester.pump();

      await tester.tapAt(topLeft + Offset(tester.getSize(canvas).width - 12, 60)); // the right end: the newest month
      await tester.pump();
      expect(find.textContaining('nov/2026: R\$ 23,00/kg · 5 vendas'), findsOneWidget);
    });

    testWidgets('is left out below three months of history', (tester) async {
      await screenWith(tester, withExtras(top: {'trend': trend.take(2).toList()}));
      expect(find.byKey(const ValueKey('price-trend')), findsNothing);
    });
  });

  group('C8: saved simulations', () {
    testWidgets('"Salvar simulação" asks for a note and posts the simulation as not used in a quote', (tester) async {
      final rig = await screenWith(tester, suggestion());
      await tester.ensureVisible(find.byKey(const ValueKey('price-sim-save')));
      await tester.tap(find.byKey(const ValueKey('price-sim-save')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('price-sim-note')), 'para a BTS');
      await tester.tap(find.text('Salvar').last);
      await tester.pumpAndSettle();
      final p = rig.posted.single;
      expect(p['shape'], 'Round');
      expect(p['diameter'], 25.4);
      expect(p['thickness'], 1.5);
      expect(p['length'], 3000);
      expect(p['pricePerKg'], 20.25);
      expect(p['pricePerPiece'], 5.62);
      expect(p['basis'], 'Neighbours');
      expect(p['confidence'], 'High');
      expect(p['note'], 'para a BTS');
      expect(p['usedInQuote'], false);
      expect(p['reason'], startsWith('Baseado em 5 vendas parecidas'));
      expect(find.text('Simulação salva.'), findsOneWidget);
    });

    testWidgets('a refused save says so and breaks nothing', (tester) async {
      final rig = await screenWith(tester, suggestion());
      rig.saveStatus = 500;
      await tester.ensureVisible(find.byKey(const ValueKey('price-sim-save')));
      await tester.tap(find.byKey(const ValueKey('price-sim-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar').last);
      await tester.pumpAndSettle();
      expect(find.text('Simulação salva.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Usar este preço" also records the simulation as used in the quote', (tester) async {
      final rig = Rig();
      final used = await openSim(tester, rig, customer: (id: 2, name: 'BTS Tubos'));
      await tester.tap(find.byKey(const ValueKey('price-sim-use')));
      await tester.pumpAndSettle();
      expect(used, ['5,62']);
      final p = rig.posted.single;
      expect(p['usedInQuote'], true);
      expect(p['customerId'], 2);
      expect(p['customerName'], 'BTS Tubos');
      expect(p['pricePerPiece'], 5.62);
    });

    testWidgets('a failure recording the use never holds the quote back', (tester) async {
      final rig = Rig()..saveStatus = 500;
      final used = await openSim(tester, rig);
      await tester.tap(find.byKey(const ValueKey('price-sim-use')));
      await tester.pumpAndSettle();
      expect(used, ['5,62']);
      expect(tester.takeException(), isNull);
    });

    Map<String, dynamic> savedRow(int id, String by, {String shape = 'Rectangular', bool used = false}) => {
      'id': id,
      'createdAt': '2026-11-04T10:00:00Z',
      'createdBy': by,
      'shape': shape,
      'diameter': shape == 'Round' ? 25.4 : null,
      'width': shape == 'Round' ? null : 40,
      'height': shape == 'Round' ? null : 20,
      'thickness': 1.5,
      'length': 3000,
      'spec': 'NBR',
      'quantity': 100,
      'customerId': 2,
      'customerName': 'BTS Tubos',
      'markupPercent': 5,
      'costPerKg': 16,
      'pricePerKg': 21,
      'pricePerPiece': 6,
      'note': 'nota $id',
      'usedInQuote': used,
    };

    testWidgets('the section lists the last 20 and tapping one puts its inputs back in the form', (tester) async {
      final rig = Rig()..saved = [savedRow(1, 'ana', used: true), savedRow(2, 'bob', shape: 'Round')];
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')), size: const Size(1400, 2400));
      expect(rig.log.where((r) => r.url.path == '/api/sales/price-simulations'), isEmpty, reason: 'loaded only when opened');
      await tester.tap(find.text('Simulações salvas'));
      await tester.pumpAndSettle();
      expect(rig.log.where((r) => r.url.path == '/api/sales/price-simulations').single.url.queryParameters['take'], '20');
      expect(find.text('usada no orçamento'), findsOneWidget);
      expect(find.textContaining('nota 1'), findsOneWidget);
      expect(find.textContaining('R\$ 21,00/kg'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('price-sim-saved-1')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(diagram(tester).profile, TubeProfile.rectangular);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('price-sim-side-a'))).controller!.text, '40');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('price-sim-side-b'))).controller!.text, '20');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('price-sim-markup'))).controller!.text, '5');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('price-sim-cost'))).controller!.text, '16');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('price-sim-quantity'))).controller!.text, '100');
      final q = rig.suggestions.last.url.queryParameters;
      expect(q['shape'], 'rect');
      expect(q['spec'], 'NBR');
      expect(q['customerId'], '2');
      expect(q['quantity'], '100');
      expect(find.text('BTS Tubos'), findsWidgets);

      // and a round one puts the round form back
      await tester.tap(find.byKey(const ValueKey('price-sim-saved-2')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(diagram(tester).profile, TubeProfile.round);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('price-sim-diameter'))).controller!.text, '25,4');
    });

    testWidgets('delete is offered for one\'s own simulations; a manager may delete any', (tester) async {
      final rig = Rig()..saved = [savedRow(1, 'ana'), savedRow(2, 'bob')];
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')), size: const Size(1400, 2400));
      await tester.tap(find.text('Simulações salvas'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-sim-saved-delete-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-saved-delete-2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('price-sim-saved-delete-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir').last);
      await tester.pumpAndSettle();
      expect(rig.deleted, ['1']);
      expect(find.byKey(const ValueKey('price-sim-saved-1')), findsNothing);

      final rig2 = Rig()..saved = [savedRow(1, 'ana'), savedRow(2, 'bob')];
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig2, 'SalesManager')), size: const Size(1400, 2400));
      await tester.tap(find.text('Simulações salvas'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-sim-saved-delete-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-saved-delete-2')), findsOneWidget);
    });

    testWidgets('an empty list says so', (tester) async {
      final rig = Rig();
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')), size: const Size(1400, 2400));
      await tester.tap(find.text('Simulações salvas'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma simulação salva ainda.'), findsOneWidget);
    });

    testWidgets('saving reloads an open list', (tester) async {
      final rig = Rig();
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')), size: const Size(1400, 2400));
      await tester.tap(find.text('Simulações salvas'));
      await tester.pumpAndSettle();
      await typeDims(tester);
      rig.saved = [savedRow(7, 'ana', shape: 'Round')];
      await tester.ensureVisible(find.byKey(const ValueKey('price-sim-save')));
      await tester.tap(find.byKey(const ValueKey('price-sim-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-sim-saved-7')), findsOneWidget);
    });
  });

  group('quote line', () {
    MoreFake fake({Map<String, dynamic>? product}) {
      final f = MoreFake();
      f.overrides['GET /api/sales/price'] = (r) => jsonResp({'productId': 7, 'unitPrice': null});
      f.overrides['GET /api/products'] = (r) => jsonResp(
        pageOf([
          product ??
              {
                'id': 7,
                'code': 'TB-25',
                'description': 'Tubo 25,4 x 1,5',
                'diameterMm': 25.4,
                'thicknessMm': 1.5,
                'lengthMm': 3000,
                'saleUnit': 'KG',
                'standard': 'DIN 2393 NBK',
              },
        ]),
      );
      f.overrides['GET /api/sales/price-history/summary'] = (r) => jsonResp({'count': 10, 'firstDate': '2020-01-01', 'lastDate': '2026-01-01'});
      f.overrides['GET /api/sales/price-suggestion'] = (r) => jsonResp(suggestion());
      return f;
    }

    Future<void> startItem(WidgetTester tester, String label) async {
      await tapKey(tester, 'quote-customer');
      await tester.tap(find.text('BTS Tubos').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'add-line');
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a rectangular product opens the rectangular form with its two sides', (tester) async {
      final f = fake(
        product: {
          'id': 7,
          'code': 'TQ-40',
          'description': 'Tubo 40 x 20',
          'shape': 'Rectangular',
          'widthMm': 40,
          'heightMm': 20,
          'thicknessMm': 1.5,
          'lengthMm': 3000,
          'saleUnit': 'PC',
        },
      );
      await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
      await startItem(tester, 'TQ-40 · Tubo 40 x 20');
      await tapKey(tester, 'suggest-price');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      final q = f.last('GET', '/api/sales/price-suggestion').url.queryParameters;
      expect(q['shape'], 'rect');
      expect(q['width'], '40');
      expect(q['height'], '20');
      expect(q['productId'], '7');
      expect(q.containsKey('diameter'), isFalse);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('price-sim-side-a'))).controller!.text, '40');
      await tapKey(tester, 'price-sim-use');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-unitPrice'))).controller!.text, '5,62'); // sold by the piece
    });

    testWidgets('editing an existing line: its product is loaded, and the line\'s own unit decides which price is handed back', (tester) async {
      final f = fake();
      f.quote['lines'] = [
        {...(f.quote['lines'] as List).first as Map<String, dynamic>, 'unitPrice': null, 'unit': 'PC'},
      ];
      // The product is sold by the kg, but this line is in pieces.
      f.overrides['GET /api/products/7'] = (r) =>
          jsonResp({'id': 7, 'code': 'TB-25', 'diameterMm': 25.4, 'thicknessMm': 1.5, 'lengthMm': 3000, 'saleUnit': 'KG'});
      await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s, quote: f.quote));
      expect(f.called('GET', '/api/products/7'), isTrue);
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('suggest-price')), findsOneWidget);
      await tapKey(tester, 'suggest-price');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(f.last('GET', '/api/sales/price-suggestion').url.queryParameters['productId'], '7');
      await tapKey(tester, 'price-sim-use');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-unitPrice'))).controller!.text, '5,62'); // per piece: the line's unit, not the product's
    });

    testWidgets('a product without a diameter (and not rectangular) gets no button instead of an empty round form', (tester) async {
      final f = fake();
      f.quote['lines'] = [
        {...(f.quote['lines'] as List).first as Map<String, dynamic>, 'unitPrice': null},
      ];
      f.overrides['GET /api/products/7'] = (r) =>
          jsonResp({'id': 7, 'code': 'XX-1', 'description': 'Barra sem diâmetro', 'shape': 'Circular', 'saleUnit': 'KG'});
      await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s, quote: f.quote));
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('suggest-price')), findsNothing);
      expect(find.byKey(const ValueKey('field-unitPrice')), findsOneWidget);
    });
  });

  group('STKM13A and GBK', () {
    test('the classes are listed in a sensible order with their labels', () {
      expect(materialSpecs.keys.toList(), ['BK', 'GBK', 'NBK', 'EN10305', 'NBR', 'SAE', 'STKM13A']);
      expect(materialSpecs['GBK'], 'GBK (DIN 2393, recozido em forno)');
      expect(materialSpecs['STKM13A'], 'STKM13A (JIS G3445)');
    });

    test('classifyMaterialSpec mirrors the server', () {
      expect(classifyMaterialSpec('EN 10305-2 – GBK'), 'GBK');
      expect(classifyMaterialSpec('EN10305-2 – BK'), 'BK');
      expect(classifyMaterialSpec('STKM13A'), 'STKM13A');
      expect(classifyMaterialSpec('JIS G3445 STKM 13 A'), 'STKM13A');
      expect(classifyMaterialSpec('stkm-13-a'), 'STKM13A');
      expect(classifyMaterialSpec('DIN 2393 NBK'), 'NBK');
      expect(classifyMaterialSpec('DIN 2393 BK'), 'BK');
      expect(classifyMaterialSpec('EN 10305-1 E355'), 'EN10305');
      expect(classifyMaterialSpec('NBR 5599'), 'NBR');
      expect(classifyMaterialSpec('SAE 1020'), 'SAE');
      expect(classifyMaterialSpec('Aço qualquer'), isNull);
      expect(classifyMaterialSpec(''), isNull);
    });

    testWidgets('the new classes are in the dropdown, and a class without sales says where the price comes from', (tester) async {
      final rig = Rig()..data = withExtras(top: {'bySpec': []});
      await openSim(tester, rig, spec: 'GBK');
      expect(rig.suggestions.first.url.queryParameters['spec'], 'GBK');
      expect(
        textOf(tester, 'price-sim-spec-note'),
        'Sem vendas de GBK no histórico: a sugestão vem de tubos de outra especificação. GBK passa pelo forno (recozimento): some o acréscimo no campo de acréscimo.',
      );
      await tester.tap(find.byKey(const ValueKey('price-sim-spec')));
      await tester.pumpAndSettle();
      expect(find.text('GBK (DIN 2393, recozido em forno)'), findsWidgets);
      expect(find.text('STKM13A (JIS G3445)'), findsOneWidget);
      await tester.tap(find.text('STKM13A (JIS G3445)').last);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(rig.suggestions.last.url.queryParameters['spec'], 'STKM13A');
      expect(textOf(tester, 'price-sim-spec-note'), contains('STKM13A é outro aço'));
    });

    testWidgets('no note when the class has sales of its own, or when no class is chosen', (tester) async {
      final data = withExtras(top: {'bySpec': []});
      ((data['similar'] as List)[0] as Map)['spec'] = 'GBK';
      await openSim(tester, Rig()..data = data, spec: 'GBK');
      expect(find.byKey(const ValueKey('price-sim-spec-note')), findsNothing);
      await openSim(tester, Rig()..data = withExtras(top: {'bySpec': []}));
      expect(find.byKey(const ValueKey('price-sim-spec-note')), findsNothing);
    });

    testWidgets('a class listed by the server in bySpec needs no note', (tester) async {
      final data = withExtras(
        top: {
          'bySpec': [
            {'spec': 'STKM13A', 'count': 2, 'medianPerKg': 30.0, 'nearestDistance': 1.0},
          ],
        },
      );
      await openSim(tester, Rig()..data = data, spec: 'STKM13A');
      expect(find.byKey(const ValueKey('price-sim-spec-note')), findsNothing);
    });
  });
}
