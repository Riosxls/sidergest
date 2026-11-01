import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/steel.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/entity_form.dart' show LookupPicker;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {'items': items, 'total': items.length, 'skip': 0, 'take': 50};

Map<String, dynamic> _lot({num balance = 200, num pending = 1}) => {
  'id': 3,
  'lotCode': 'B-100',
  'supplierId': 1,
  'supplierName': 'Usina Sul',
  'purchaseInvoice': '123',
  'receivedDate': '2026-10-01',
  'specification': 'DC01',
  'thickness': 1.5,
  'width': 1200,
  'weightKg': 1000,
  'pricePerKg': 6,
  'purchaseValue': 6000,
  'sentKg': 800,
  'returnedKg': 400,
  'scrapKg': 20,
  'usedKg': 100,
  'serviceCost': 300,
  'laborCost': 50,
  'balanceKg': balance,
  'balanceValue': balance * 6,
  'totalCost': 6350,
  'pendingJobs': pending,
  'notes': 'Bobina de teste',
  'createdAt': '2026-10-01T10:00:00Z',
};

Map<String, dynamic> _job({int id = 9, bool returned = false}) => {
  'id': id,
  'lotId': 3,
  'lotCode': 'B-100',
  'processorId': 2,
  'processorName': 'Açoservice',
  'shipmentInvoice': 'N$id',
  'shipmentDate': '2026-10-02',
  'sentKg': 400,
  'returnInvoice': returned ? 'R$id' : null,
  'returnDate': returned ? '2026-10-10' : null,
  'finishedKg': returned ? 380 : null,
  'scrapKg': returned ? 20 : null,
  'lossPercent': returned ? 5 : null,
  'serviceCost': returned ? 300 : null,
  'returned': returned,
  'notes': null,
};

final _usage = {'id': 4, 'lotId': 3, 'lotCode': 'B-100', 'date': '2026-10-15', 'kg': 100, 'laborCost': 50, 'reference': 'OF 12', 'notes': null};

class _Fake {
  final log = <http.Request>[];
  var role = 'Stock';
  Map<String, dynamic> lot = _lot();
  List<Map<String, dynamic>> jobs = [_job(), _job(id: 10, returned: true)];
  List<Map<String, dynamic>> usages = [_usage];
  List<Map<String, dynamic>> lots = [_lot()];
  int lotStatus = 200;
  int deleteStatus = 204;

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);
  bool has(String method, String path) => log.any((r) => r.method == method && r.url.path == path);

  late final client = MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    final m = r.method;
    if (p == '/api/suppliers') {
      return _json(_page([{'id': 2, 'code': 'S2', 'name': 'Açoservice'}, {'id': 1, 'code': 'S1', 'name': 'Usina Sul'}]));
    }
    if (p == '/api/steel/lots' && m == 'GET') return _json(_page(lots));
    if (p == '/api/steel/lots' && m == 'POST') return _json({..._lot(), 'id': 3}, 201);
    if (p == '/api/steel/lots/3' && m == 'GET') {
      if (lotStatus != 200) return _json({'title': 'Erro', 'detail': 'Lote indisponível', 'status': lotStatus}, lotStatus);
      return _json(lot);
    }
    if (p == '/api/steel/lots/3' && m == 'PUT') return _json(lot);
    if (p == '/api/steel/lots/3' && m == 'DELETE') {
      if (deleteStatus == 204) return http.Response('', 204);
      return _json({'title': 'Conflito', 'detail': 'Lote tem remessas', 'status': deleteStatus}, deleteStatus);
    }
    if (p == '/api/steel/lots/3/slitter') return _json(jobs);
    if (p == '/api/steel/lots/3/usages') return _json(usages);
    if (p == '/api/steel/slitter' && m == 'GET') return _json(_page(jobs));
    if (p == '/api/steel/slitter' && m == 'POST') return _json({'id': 20}, 201);
    if (p.startsWith('/api/steel/slitter/') && m == 'PUT') return _json({'id': 9});
    if (p.startsWith('/api/steel/slitter/') && m == 'DELETE') return http.Response('', 204);
    if (p == '/api/steel/usages' && m == 'GET') return _json(_page(usages));
    if (p == '/api/steel/usages' && m == 'POST') return _json({'id': 21}, 201);
    if (p.startsWith('/api/steel/usages/') && m == 'PUT') return _json({'id': 4});
    if (p.startsWith('/api/steel/usages/') && m == 'DELETE') return http.Response('', 204);
    return _json(_page([]));
  });
}

Future<Session> _pump(WidgetTester tester, _Fake fake, Widget Function(Session s) screen) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: fake.client, token: 'tok'))
    ..username = 'ana'
    ..role = fake.role
    ..permissions = rolePermissions[fake.role]!;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: screen(session),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _pickLookup(WidgetTester tester, String label, String display) async {
  await tester.tap(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(LookupPicker), matching: find.text(display)));
  await tester.pumpAndSettle();
}

Future<void> _tapTip(WidgetTester tester, String tip, {bool first = false}) async {
  final f = first ? find.byTooltip(tip).first : find.byTooltip(tip).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openLotMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const ValueKey('lot-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  group('lista de aço', () {
    testWidgets('a stock user creates a coil and lands on its screen', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => Scaffold(body: SteelScreen(session: s)));
      expect(find.text('1 pendente(s)'), findsOneWidget);
      await tester.tap(find.text('Nova bobina'));
      await tester.pumpAndSettle();
      expect(find.text('Nova bobina'), findsNWidgets(2));
      await tester.enterText(find.byKey(const ValueKey('field-lotCode')), 'B-200');
      await _pickLookup(tester, 'Fornecedor (usina) *', 'S2 · Açoservice');
      await tester.enterText(find.byKey(const ValueKey('field-weightKg')), '1500');
      await tester.enterText(find.byKey(const ValueKey('field-pricePerKg')), '6,5');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/steel/lots'));
      expect(b['lotCode'], 'B-200');
      expect(b['supplierId'], 2);
      expect(b['weightKg'], 1500);
      expect(b['pricePerKg'], 6.5);
      expect(find.text('B-100 · Usina Sul'), findsOneWidget);
      expect(fake.has('GET', '/api/steel/lots/3/slitter'), isTrue);
    });

    testWidgets('required coil fields are validated before posting', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => Scaffold(body: SteelScreen(session: s)));
      await tester.tap(find.text('Nova bobina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/steel/lots'), isFalse);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('a lot with negative balance is listed and tapping opens its screen', (tester) async {
      final fake = _Fake()
        ..lots = [_lot(balance: -30, pending: 0)]
        ..lot = _lot(balance: -30, pending: 0);
      await _pump(tester, fake, (s) => Scaffold(body: SteelScreen(session: s)));
      expect(find.text('-30'), findsOneWidget);
      await tester.tap(find.text('Usina Sul'));
      await tester.pumpAndSettle();
      expect(find.text('Consumo maior que o saldo'), findsOneWidget);
    });

    testWidgets('slitter tab: a stock user sends a new shipment and edits an existing one', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => Scaffold(body: SteelScreen(session: s)));
      await tester.tap(find.byKey(const ValueKey('steel-tab-slitter')));
      await tester.pumpAndSettle();
      expect(find.text('No slitter'), findsOneWidget);
      expect(find.text('Retornou'), findsOneWidget);
      expect(find.text('5,00'), findsOneWidget);
      await tester.tap(find.text('Nova remessa'));
      await tester.pumpAndSettle();
      await _pickLookup(tester, 'Lote / bobina *', 'B-100');
      await _pickLookup(tester, 'Beneficiador (slitter) *', 'S2 · Açoservice');
      await tester.enterText(find.byKey(const ValueKey('field-sentKg')), '500');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/steel/slitter'));
      expect(b['lotId'], 3);
      expect(b['processorId'], 2);
      expect(b['sentKg'], 500);

      await tester.tap(find.text('N9'));
      await tester.pumpAndSettle();
      expect(find.text('Remessa N9'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-sentKg')), '410');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final put = fake.body(fake.last('PUT', '/api/steel/slitter/9'));
      expect(put['sentKg'], 410);
      expect(put['lotId'], 3);
      expect(put['processorId'], 2);
    });

    testWidgets('slitter tab: a reader taps a shipment and goes to the lot', (tester) async {
      final fake = _Fake()..role = 'Reader';
      await _pump(tester, fake, (s) => Scaffold(body: SteelScreen(session: s)));
      await tester.tap(find.byKey(const ValueKey('steel-tab-slitter')));
      await tester.pumpAndSettle();
      expect(find.text('Nova remessa'), findsNothing);
      await tester.tap(find.text('N9'));
      await tester.pumpAndSettle();
      expect(find.text('B-100 · Usina Sul'), findsOneWidget);
      expect(find.text('Remessa N9'), findsNothing);
    });

    testWidgets('usage tab: record a consumption and edit an existing one', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => Scaffold(body: SteelScreen(session: s)));
      await tester.tap(find.byKey(const ValueKey('steel-tab-usage')));
      await tester.pumpAndSettle();
      expect(find.text('OF 12'), findsOneWidget);
      await tester.tap(find.text('Novo consumo'));
      await tester.pumpAndSettle();
      await _pickLookup(tester, 'Lote / bobina *', 'B-100');
      await tester.enterText(find.byKey(const ValueKey('field-kg')), '75,5');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/steel/usages'));
      expect(b['lotId'], 3);
      expect(b['kg'], 75.5);
      expect(b['laborCost'], 0);

      await tester.tap(find.text('OF 12'));
      await tester.pumpAndSettle();
      expect(find.text('Uso interno · B-100'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-reference')), 'OF 13');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final put = fake.body(fake.last('PUT', '/api/steel/usages/4'));
      expect(put['reference'], 'OF 13');
      expect(put['kg'], 100);
    });

    testWidgets('usage tab: a reader cannot edit a consumption', (tester) async {
      final fake = _Fake()..role = 'Reader';
      await _pump(tester, fake, (s) => Scaffold(body: SteelScreen(session: s)));
      await tester.tap(find.byKey(const ValueKey('steel-tab-usage')));
      await tester.pumpAndSettle();
      expect(find.text('Novo consumo'), findsNothing);
      await tester.tap(find.text('OF 12'));
      await tester.pumpAndSettle();
      expect(find.text('Uso interno · B-100'), findsNothing);
    });
  });

  group('tela do lote', () {
    testWidgets('KPIs show the loss of the returned jobs and the cost breakdown', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      expect(find.text('Saldo (kg)'), findsOneWidget);
      expect(find.text('1 remessa(s) pendente(s)'), findsOneWidget);
      expect(find.textContaining('perda 5,00%'), findsOneWidget);
      expect(find.text('Slitter (2)'), findsOneWidget);
      expect(find.text('Uso interno (1)'), findsOneWidget);
      expect(find.text('Bobina de teste'), findsOneWidget);
    });

    testWidgets('negative balance is flagged on the KPI', (tester) async {
      final fake = _Fake()..lot = _lot(balance: -10);
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      expect(find.text('Consumo maior que o saldo'), findsOneWidget);
    });

    testWidgets('a load error is shown in place of the lot', (tester) async {
      final fake = _Fake()..lotStatus = 500;
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      expect(find.text('Lote de aço'), findsOneWidget);
      expect(find.textContaining('Lote indisponível'), findsOneWidget);
      expect(find.byKey(const ValueKey('lot-menu')), findsNothing);
    });

    testWidgets('a reader sees the lot without any action', (tester) async {
      final fake = _Fake()..role = 'Reader';
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      expect(find.byKey(const ValueKey('lot-menu')), findsNothing);
      expect(find.byKey(const ValueKey('lot-new-job')), findsNothing);
      expect(find.byKey(const ValueKey('lot-new-usage')), findsNothing);
      expect(find.byKey(const ValueKey('job-return-9')), findsNothing);
      expect(find.byTooltip('Editar'), findsNothing);
    });

    testWidgets('edit lot sends the full lot to PUT and reloads', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      final loads = fake.log.where((r) => r.url.path == '/api/steel/lots/3' && r.method == 'GET').length;
      await _openLotMenu(tester, 'Editar lote');
      expect(find.text('Editar B-100'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-specification')), 'DC04');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('PUT', '/api/steel/lots/3'));
      expect(b['specification'], 'DC04');
      expect(b['supplierId'], 1);
      expect(b['weightKg'], 1000);
      expect(fake.log.where((r) => r.url.path == '/api/steel/lots/3' && r.method == 'GET').length, loads + 1);
    });

    testWidgets('delete lot asks for confirmation and goes back', (tester) async {
      final fake = _Fake();
      await _pump(
        tester,
        fake,
        (s) => Builder(
          builder: (c) => Scaffold(
            body: TextButton(onPressed: () => openSteelLot(c, s, 3), child: const Text('abrir lote')),
          ),
        ),
      );
      await tester.tap(find.text('abrir lote'));
      await tester.pumpAndSettle();
      await _openLotMenu(tester, 'Excluir lote');
      expect(find.text('Excluir B-100?'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(fake.has('DELETE', '/api/steel/lots/3'), isFalse);
      await _openLotMenu(tester, 'Excluir lote');
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(fake.has('DELETE', '/api/steel/lots/3'), isTrue);
      expect(find.text('abrir lote'), findsOneWidget);
    });

    testWidgets('delete lot failure shows the API message and stays', (tester) async {
      final fake = _Fake()..deleteStatus = 409;
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      await _openLotMenu(tester, 'Excluir lote');
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lote tem remessas'), findsOneWidget);
      expect(find.text('B-100 · Usina Sul'), findsOneWidget);
    });

    testWidgets('new shipment from the lot presets the lot and posts', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      await tester.ensureVisible(find.byKey(const ValueKey('lot-new-job')));
      await tester.tap(find.byKey(const ValueKey('lot-new-job')));
      await tester.pumpAndSettle();
      await _pickLookup(tester, 'Beneficiador (slitter) *', 'S2 · Açoservice');
      await tester.enterText(find.byKey(const ValueKey('field-sentKg')), '300');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/steel/slitter'));
      expect(b['lotId'], 3);
      expect(b['processorId'], 2);
      expect(b['sentKg'], 300);
    });

    testWidgets('edit shipment from the lot table', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      await _tapTip(tester, 'Editar', first: true);
      await tester.pumpAndSettle();
      expect(find.text('Remessa N9'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-shipmentInvoice')), 'N99');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('PUT', '/api/steel/slitter/9'))['shipmentInvoice'], 'N99');
    });

    testWidgets('returned shipment has no return button; remove asks first', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      expect(find.byKey(const ValueKey('job-return-10')), findsNothing);
      await _tapTip(tester, 'Remover', first: true);
      await tester.pumpAndSettle();
      expect(find.text('Remover remessa?'), findsOneWidget);
      expect(find.text('O saldo do lote é recalculado.'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(fake.log.any((r) => r.method == 'DELETE'), isFalse);
      await _tapTip(tester, 'Remover', first: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(fake.has('DELETE', '/api/steel/slitter/9'), isTrue);
    });

    testWidgets('new, edit and remove an internal consumption from the lot', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
      await tester.ensureVisible(find.byKey(const ValueKey('lot-new-usage')));
      await tester.tap(find.byKey(const ValueKey('lot-new-usage')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-kg')), '40');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/steel/usages'));
      expect(b['lotId'], 3);
      expect(b['kg'], 40);
      expect(b['laborCost'], 0);

      // The usage row is the last "Editar" / "Remover" in the page (jobs come first).
      await _tapTip(tester, 'Editar');
      await tester.pumpAndSettle();
      expect(find.text('Uso interno · B-100'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-kg')), '90');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('PUT', '/api/steel/usages/4'))['kg'], 90);

      await _tapTip(tester, 'Remover');
      await tester.pumpAndSettle();
      expect(find.text('Remover consumo?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(fake.has('DELETE', '/api/steel/usages/4'), isTrue);
    });
  });
}
