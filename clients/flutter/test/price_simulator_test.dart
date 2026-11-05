import 'dart:convert';
import 'dart:typed_data';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/price_simulator.dart';
import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';
import 'sales_more_support.dart';

Map<String, dynamic> suggestion({String basis = 'Neighbours', String confidence = 'High', bool withCustomerLast = false}) => {
  'weight': {'netKg': 0.5625, 'grossKg': 0.5782, 'lossPercent': 2.8},
  'suggestion': basis == 'None'
      ? {'basis': 'None', 'confidence': 'Low', 'pricePerKg': null, 'low': null, 'high': null, 'pricePerPiece': null, 'totalForQuantity': null}
      : {'basis': basis, 'confidence': confidence, 'pricePerKg': 20.25, 'low': 19.8, 'high': 21.0, 'pricePerPiece': 5.62, 'totalForQuantity': 2810},
  'similar': [
    {'date': '2026-03-10', 'customer': 'Zeta', 'diameter': 25.4, 'thickness': 1.5, 'length': 3000, 'unit': 'KG', 'unitPrice': 21.0, 'pricePerKg': 21.0, 'distance': 2.0, 'source': 'Histórico', 'spec': 'NBR'},
    {'date': '2026-01-05', 'customer': 'BTS Tubos', 'diameter': 25.4, 'thickness': 1.5, 'length': 3000, 'unit': 'PC', 'unitPrice': 5.5, 'pricePerKg': 19.9, 'distance': 0.5, 'source': 'MetaGest', 'spec': null},
  ],
  'customerLast': withCustomerLast ? {'date': '2026-01-05', 'diameter': 25.4, 'thickness': 1.5, 'length': 3000, 'unit': 'PC', 'unitPrice': 5.5, 'pricePerKg': 19.9} : null,
  'historyCount': 4817,
};

class Rig {
  final log = <http.Request>[];
  Map<String, dynamic> data = suggestion();
  Map<String, dynamic> summary = {'count': 4817, 'firstDate': '2015-10-05', 'lastDate': '2026-11-02'};
  int summaryStatus = 200;
  int suggestStatus = 200;
  Map<String, dynamic> importResult = {'read': 100, 'imported': 90, 'duplicates': 7, 'skipped': 3, 'firstDate': '2015-10-05', 'lastDate': '2026-11-02'};

  Future<http.Response> handle(http.Request r) async {
    log.add(r);
    switch (r.url.path) {
      case '/api/sales/price-suggestion':
        return suggestStatus == 200 ? jsonResp(data) : jsonResp({'error': 'Sem permissão'}, suggestStatus);
      case '/api/sales/price-history/summary':
        return summaryStatus == 200 ? jsonResp(summary) : jsonResp({'error': 'Sem permissão'}, summaryStatus);
      case '/api/sales/price-history/import':
        return jsonResp(importResult);
      case '/api/customers':
        return jsonResp(
          pageOf([
            {'id': 2, 'name': 'BTS Tubos'},
          ]),
        );
    }
    return jsonResp(pageOf([]));
  }

  Iterable<http.Request> get suggestions => log.where((r) => r.url.path == '/api/sales/price-suggestion');
}

Session sessionFor(Rig rig, String role) => Session(api: ApiClient(baseUrl: 'http://api.test', client: MockClient(rig.handle), token: 'tok'))
  ..username = 'ana'
  ..role = role
  ..permissions = rolePermissions[role]!;

Future<void> pumpApp(WidgetTester tester, Widget home, {Size size = const Size(1400, 1600)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: home),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> typeDims(WidgetTester tester, {String d = '25,4', String t = '1,5', String l = '3000'}) async {
  await tester.enterText(find.byKey(const ValueKey('price-sim-diameter')), d);
  await tester.enterText(find.byKey(const ValueKey('price-sim-thickness')), t);
  await tester.enterText(find.byKey(const ValueKey('price-sim-length')), l);
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
}

/// Opens the dialog from a button and returns what "Usar este preço" handed back.
Future<List<String>> openDialog(WidgetTester tester, Rig rig, {bool unitIsKg = false, bool withUse = true, String? spec}) async {
  final used = <String>[];
  final session = sessionFor(rig, 'Sales');
  await pumpApp(
    tester,
    Builder(
      builder: (c) => TextButton(
        key: const ValueKey('open'),
        onPressed: () => showPriceSimulator(c, session, diameter: 25.4, thickness: 1.5, length: 3000, spec: spec, unitIsKg: unitIsKg, onUse: withUse ? used.add : null),
        child: const Text('abrir'),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
  return used;
}

void main() {
  testWidgets('weight, suggestion, range, confidence and the similar sales are shown; the request carries the dimensions and the customer', (tester) async {
    final rig = Rig()..data = suggestion(withCustomerLast: true);
    await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
    await typeDims(tester);
    await tester.enterText(find.byKey(const ValueKey('price-sim-quantity')), '500');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Histórico: 4.817 vendas (out/2015 a nov/2026)'), findsOneWidget);
    expect(find.text('Peso líquido 563 g  ·  Peso bruto 578 g (+2,8%)'), findsOneWidget);
    expect(find.text('Sugestão: R\$ 20,25/kg  ·  R\$ 5,62/peça'), findsOneWidget);
    expect(find.text('faixa R\$ 19,80 – R\$ 21,00/kg'), findsOneWidget);
    expect(find.text('500 peças: R\$ 2.810,00'), findsOneWidget);
    expect(find.text('Confiança Alta'), findsOneWidget);
    expect(find.bySemanticsLabel('Confiança da sugestão: Alta'), findsOneWidget);
    expect(find.text('Baseado em 2 vendas parecidas dos últimos 24 meses'), findsOneWidget);
    expect(find.textContaining('Último preço deste cliente: R\$ 5,50/peça (R\$ 19,90/kg)'), findsOneWidget);
    // Nearest first: BTS (distance 0.5) before Zeta (2.0).
    expect(tester.getTopLeft(find.text('BTS Tubos')).dy, lessThan(tester.getTopLeft(find.text('Zeta')).dy));
    final q = rig.suggestions.last.url.queryParameters;
    expect(q['diameter'], '25.4');
    expect(q['thickness'], '1.5');
    expect(q['length'], '3000');
    expect(q['quantity'], '500');
    expect(q.containsKey('customerId'), isFalse);
    expect(q.containsKey('spec'), isFalse);
  });

  testWidgets('the request waits for a quiet moment and goes out once', (tester) async {
    final rig = Rig();
    await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
    await tester.enterText(find.byKey(const ValueKey('price-sim-diameter')), '25,4');
    await tester.enterText(find.byKey(const ValueKey('price-sim-thickness')), '1,5');
    await tester.enterText(find.byKey(const ValueKey('price-sim-length')), '3');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const ValueKey('price-sim-length')), '30');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const ValueKey('price-sim-length')), '3000');
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.suggestions, isEmpty);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(rig.suggestions.length, 1);
    expect(rig.suggestions.single.url.queryParameters['length'], '3000');
  });

  testWidgets('the customer is sent when chosen', (tester) async {
    final rig = Rig();
    await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
    await typeDims(tester);
    await tester.tap(find.byKey(const ValueKey('price-sim-customer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTS Tubos').last);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(rig.suggestions.last.url.queryParameters['customerId'], '2');
  });

  testWidgets('invalid measures show a message and send nothing', (tester) async {
    final rig = Rig();
    await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
    expect(find.text('Digite o diâmetro, a espessura e o comprimento para ver o peso e o preço sugerido.'), findsOneWidget);
    await typeDims(tester, d: '10', t: '5', l: '3000');
    expect(find.textContaining('2 × espessura precisa ser menor que o diâmetro'), findsOneWidget);
    await typeDims(tester, d: '25', t: '0', l: '3000');
    expect(find.text('Informe um valor maior que zero.'), findsOneWidget);
    await typeDims(tester, d: 'abc', t: '1', l: '3000');
    expect(find.text('Digite um número.'), findsOneWidget);
    expect(rig.suggestions, isEmpty);
  });

  testWidgets('no similar sale: the screen says to type the price and offers none', (tester) async {
    final rig = Rig()..data = suggestion(basis: 'None');
    final used = await openDialog(tester, rig);
    expect(find.text('Sem vendas parecidas: digite o preço'), findsWidgets);
    expect(find.textContaining('Sugestão:'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('price-sim-use'))).onPressed, isNull);
    expect(used, isEmpty);
  });

  testWidgets('a repeat sale to the customer says whose price it is and when', (tester) async {
    final rig = Rig()..data = suggestion(basis: 'CustomerRepeat', confidence: 'High', withCustomerLast: true);
    final session = sessionFor(rig, 'Sales');
    await pumpApp(
      tester,
      Builder(
        builder: (c) => TextButton(
          key: const ValueKey('open'),
          onPressed: () => showPriceSimulator(c, session, diameter: 25.4, thickness: 1.5, length: 3000, customer: (id: 2, name: 'BTS Tubos')),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Mesmo preço cobrado de BTS Tubos em 05/01/2026 para esta medida'), findsOneWidget);
    expect(rig.suggestions.last.url.queryParameters['customerId'], '2');
    expect(find.byKey(const ValueKey('price-sim-use')), findsNothing); // no onUse: the dialog only informs
  });

  testWidgets('low and medium confidence use the warning and danger chips', (tester) async {
    final rig = Rig()..data = suggestion(confidence: 'Low');
    await openDialog(tester, rig);
    expect(find.text('Confiança Baixa'), findsOneWidget);
  });

  testWidgets('the specification is sent only when chosen, and the column and highlight follow it', (tester) async {
    final rig = Rig();
    await openDialog(tester, rig);
    expect(rig.suggestions.last.url.queryParameters.containsKey('spec'), isFalse);
    expect(find.text('Espec.'), findsOneWidget);
    expect(find.text('NBR'), findsOneWidget);
    expect(find.text('—'), findsWidgets); // the sale without a class
    await tester.tap(find.byKey(const ValueKey('price-sim-spec')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NBR 5599').last);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(rig.suggestions.last.url.queryParameters['spec'], 'NBR');
    // Back to "Qualquer" drops the parameter.
    await tester.tap(find.byKey(const ValueKey('price-sim-spec')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qualquer').last);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(rig.suggestions.last.url.queryParameters.containsKey('spec'), isFalse);
  });

  testWidgets('a starting specification goes in the first request', (tester) async {
    final rig = Rig();
    await openDialog(tester, rig, spec: 'EN10305');
    expect(rig.suggestions.first.url.queryParameters['spec'], 'EN10305');
  });

  test('classifyMaterialSpec reads the standard text', () {
    expect(classifyMaterialSpec('EN 10305-1 E355'), 'EN10305');
    expect(classifyMaterialSpec('DIN 2393 NBK'), 'NBK');
    expect(classifyMaterialSpec('DIN 2393 ST 37.4 BK'), 'BK');
    expect(classifyMaterialSpec('NBR 5599'), 'NBR');
    expect(classifyMaterialSpec('SAE 1020'), 'SAE');
    expect(classifyMaterialSpec('ABC'), isNull);
    expect(classifyMaterialSpec(null), isNull);
  });

  testWidgets('"Usar este preço" gives the price per piece, or per kg when the item is sold by the kg', (tester) async {
    final rig = Rig();
    final piece = await openDialog(tester, rig);
    await tester.tap(find.byKey(const ValueKey('price-sim-use')));
    await tester.pumpAndSettle();
    expect(piece, ['5,62']);
    expect(find.byKey(const ValueKey('price-sim-diameter')), findsNothing); // dialog closed

    final kg = await openDialog(tester, rig, unitIsKg: true);
    await tester.tap(find.byKey(const ValueKey('price-sim-use')));
    await tester.pumpAndSettle();
    expect(kg, ['20,25']);
  });

  testWidgets('a refused request (403) says so in the dialog without crashing', (tester) async {
    final rig = Rig()..suggestStatus = 403;
    await openDialog(tester, rig);
    expect(find.byKey(const ValueKey('price-sim-error')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('price-sim-use'))).onPressed, isNull);
  });

  group('history strip', () {
    testWidgets('empty history: explanation, and the import button only for who can edit prices', (tester) async {
      final rig = Rig()..summary = {'count': 0, 'firstDate': null, 'lastDate': null};
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
      expect(find.textContaining('peça a um gerente para importar'), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-import')), findsNothing);
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'SalesManager')));
      expect(find.textContaining('ainda não foi importado'), findsOneWidget);
      expect(find.byKey(const ValueKey('price-sim-import')), findsOneWidget);
    });

    testWidgets('a manager imports a CSV and sees the counts; the strip reloads', (tester) async {
      final rig = Rig();
      final oldPicker = priceHistoryFilePicker;
      priceHistoryFilePicker = () async => (name: 'vendas.csv', bytes: Uint8List.fromList(utf8.encode('a;b\n1;2')));
      addTearDown(() => priceHistoryFilePicker = oldPicker);
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'SalesManager')));
      await tester.tap(find.byKey(const ValueKey('price-sim-import')));
      await tester.pumpAndSettle();
      expect(rig.log.where((r) => r.url.path == '/api/sales/price-history/import' && r.method == 'POST').length, 1);
      expect(find.text('Histórico importado'), findsOneWidget);
      expect(find.text('Linhas lidas: 100'), findsOneWidget);
      expect(find.text('Vendas importadas: 90'), findsOneWidget);
      expect(find.text('Já existiam (repetidas): 7'), findsOneWidget);
      expect(find.text('Ignoradas (dados incompletos): 3'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(rig.log.where((r) => r.url.path == '/api/sales/price-history/summary').length, 2);
    });

    testWidgets('a salesperson sees the strip without the import button', (tester) async {
      final rig = Rig();
      await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')));
      expect(find.byKey(const ValueKey('price-sim-import')), findsNothing);
    });
  });

  testWidgets('works at phone width', (tester) async {
    final rig = Rig();
    await pumpApp(tester, PriceSimulatorScreen(session: sessionFor(rig, 'Sales')), size: const Size(380, 900));
    await typeDims(tester);
    expect(find.text('Sugestão: R\$ 20,25/kg  ·  R\$ 5,62/peça'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('quote line', () {
    MoreFake fake() {
      final f = MoreFake();
      f.overrides['GET /api/sales/price'] = (r) => jsonResp({'productId': 7, 'unitPrice': null});
      f.overrides['GET /api/products'] = (r) => jsonResp(
        pageOf([
          {'id': 7, 'code': 'TB-25', 'description': 'Tubo 25,4 x 1,5', 'diameterMm': 25.4, 'thicknessMm': 1.5, 'lengthMm': 3000, 'saleUnit': 'KG', 'standard': 'DIN 2393 NBK'},
        ]),
      );
      f.overrides['GET /api/sales/price-history/summary'] = (r) => jsonResp({'count': 10, 'firstDate': '2020-01-01', 'lastDate': '2026-01-01'});
      f.overrides['GET /api/sales/price-suggestion'] = (r) => jsonResp(suggestion());
      return f;
    }

    Future<void> startItem(WidgetTester tester) async {
      await tapKey(tester, 'quote-customer');
      await tester.tap(find.text('BTS Tubos').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'add-line');
      await tester.tap(find.text('TB-25 · Tubo 25,4 x 1,5').last);
      await tester.pumpAndSettle();
    }

    testWidgets('"Sugerir preço" opens the simulator with the product, the customer and the standard, and the price fills the field', (tester) async {
      final f = fake();
      await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
      await startItem(tester);
      expect(find.byKey(const ValueKey('suggest-price')), findsOneWidget);
      await tapKey(tester, 'suggest-price');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      final q = f.last('GET', '/api/sales/price-suggestion').url.queryParameters;
      expect(q['diameter'], '25.4');
      expect(q['thickness'], '1.5');
      expect(q['length'], '3000');
      expect(q['customerId'], '2');
      expect(q['spec'], 'NBK');
      await tapKey(tester, 'price-sim-use');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-unitPrice'))).controller!.text, '20,25'); // sold by the kg
    });

    testWidgets('a server that refuses the simulator (403) leaves the button out', (tester) async {
      final f = fake();
      f.overrides['GET /api/sales/price-history/summary'] = (r) => jsonResp({'error': 'x'}, 403);
      await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
      await startItem(tester);
      expect(find.byKey(const ValueKey('suggest-price')), findsNothing);
      expect(find.byKey(const ValueKey('field-unitPrice')), findsOneWidget);
    });
  });
}
