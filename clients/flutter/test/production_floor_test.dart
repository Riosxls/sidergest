import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/production_floor.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {'items': items, 'total': items.length, 'skip': 0, 'take': 50};

final _report = {
  'id': 31,
  'reference': 'OF 12',
  'operationSequence': 10,
  'date': '2026-10-28',
  'employeeName': 'Carlos',
  'machineCode': 'PERF-1',
  'startTime': '07:00:00',
  'endTime': '11:30:00',
  'hours': 4.5,
  'goodQuantity': 40,
  'scrapQuantity': 2,
  'downtimeHours': 0,
  'outsideShipmentId': 5,
  'notes': 'Sem paradas',
  'reportedBy': 'pcp',
  'reportedAt': '2026-10-28T12:00:00Z',
};

final _shipment = {
  'id': 5,
  'orderId': 7,
  'reference': 'OF 12',
  'operationSequence': 20,
  'supplierName': 'Galvano Sul',
  'sentOn': '2026-10-20',
  'quantity': 100,
  'returnedQuantity': 20,
  'scrapQuantity': 0,
  'open': 80,
  'serviceValue': 200,
  'invoiceNumber': '123',
};

Map<String, dynamic> _order(List<Map<String, dynamic>> ops) => {
  'id': 7,
  'kind': 'Standard',
  'number': 12,
  'reference': 'OF 12',
  'productId': 3,
  'productCode': 'TB-50',
  'productName': 'Tubo 50x50',
  'productUnit': 'PC',
  'customerId': null,
  'customerName': null,
  'quantity': 100,
  'dueDate': '2026-01-10',
  'status': 'Released',
  'parentOrderId': null,
  'createdAt': '2026-10-20T10:00:00Z',
  'good': 0,
  'scrap': 0,
  'received': 0,
  'receivable': 0,
  'workInProcess': 0,
  'operations': ops,
  'materials': [],
  'children': [],
  'warnings': [],
};

Map<String, dynamic> _op(int seq, {String? description, bool external = false, num remaining = 60}) => {
  'id': seq,
  'sequence': seq,
  'description': description,
  'machineId': 1,
  'machineCode': 'M$seq',
  'workCenterId': 1,
  'setupHours': 0,
  'piecesPerHour': 50,
  'operators': 1,
  'external': external,
  'supplierId': null,
  'externalLeadDays': null,
  'plannedHours': 1,
  'good': 0,
  'scrap': 0,
  'inTransit': 0,
  'overrunReleased': 0,
  'limit': 100,
  'remaining': remaining,
};

class _Fake {
  final log = <http.Request>[];
  var role = 'Production';
  List<Map<String, dynamic>> reports = [_report];
  List<Map<String, dynamic>> shipments = [_shipment];
  List<Map<String, dynamic>> ops = [_op(10, description: 'Perfilar'), _op(20, description: 'Trefilar')];
  Object? load = [
    {'id': 1, 'code': 'PERF-1', 'weekStart': '2026-10-26', 'hours': 44, 'capacity': 40, 'loadPercent': 110, 'operations': 3},
    {'id': 1, 'code': 'PERF-1', 'weekStart': '2026-11-02', 'hours': 36, 'capacity': 40, 'loadPercent': 90, 'operations': 2},
    {'id': 2, 'code': 'TREF-1', 'weekStart': '2026-10-26', 'hours': 10, 'capacity': 40, 'loadPercent': 25, 'operations': 1},
  ];
  int loadStatus = 200;

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);
  bool has(String method, String path) => log.any((r) => r.method == method && r.url.path == path);

  MockClient get client => MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    final m = r.method;
    if (p == '/api/production/reports' && m == 'GET') return _json(_page(reports));
    if (p == '/api/production/reports' && m == 'POST') return _json({'id': 99}, 201);
    if (p.startsWith('/api/production/reports/') && m == 'DELETE') return http.Response('', 204);
    if (p == '/api/production/outside-shipments' && m == 'GET') return _json(shipments);
    if (p.endsWith('/returns') && m == 'POST') return _json({'id': 1}, 201);
    if (p == '/api/production/orders' && m == 'GET') {
      return _json(_page([{'id': 7, 'number': 12, 'reference': 'OF 12'}]));
    }
    if (p == '/api/production/orders/7') return _json(_order(ops));
    if (p == '/api/production/load') {
      if (loadStatus != 200) return _json({'title': 'Erro', 'detail': 'Carga indisponível', 'status': loadStatus}, loadStatus);
      return _json(load);
    }
    if (p == '/api/production/schedule' && m == 'POST') return _json([]);
    return _json(_page([]));
  });
}

Future<Session> _pump(WidgetTester tester, _Fake fake, Widget Function(Session s) screen) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: fake.client, token: 'tok'))
    ..username = 'u'
    ..role = fake.role
    ..permissions = rolePermissions[fake.role]!;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: screen(session)),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

void main() {
  group('apontamentos', () {
    testWidgets('a producer opens a report, sees the details and deletes it after confirming', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => ReportsScreen(session: s));
      expect(find.text('Carlos'), findsOneWidget);
      expect(find.text('Novo apontamento'), findsOneWidget);
      await tester.tap(find.text('Carlos'));
      await tester.pumpAndSettle();
      expect(find.text('Apontamento OF 12 · op. 10'), findsOneWidget);
      expect(find.text('07:00 – 11:30'), findsOneWidget);
      expect(find.text('Remessa 5'), findsOneWidget);
      expect(find.text('Sem paradas'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('report-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Excluir este apontamento?'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(fake.has('DELETE', '/api/production/reports/31'), isTrue);
      expect(find.text('Apontamento excluído'), findsOneWidget);
    });

    testWidgets('declining the confirmation keeps the report', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => ReportsScreen(session: s));
      await tester.tap(find.text('Carlos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(fake.log.any((r) => r.method == 'DELETE'), isFalse);
    });

    testWidgets('a reader sees the report without delete and without the new button', (tester) async {
      final fake = _Fake()..role = 'Reader';
      await _pump(tester, fake, (s) => ReportsScreen(session: s));
      expect(find.text('Novo apontamento'), findsNothing);
      await tester.tap(find.text('Carlos'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('report-delete')), findsNothing);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Apontamento OF 12 · op. 10'), findsNothing);
    });

    testWidgets('the date filter chip sends the chosen day and the other chip stays empty', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => ReportsScreen(session: s));
      expect(find.text('De'), findsOneWidget);
      expect(find.text('Até'), findsOneWidget);
      await tester.tap(find.text('De'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('De'), findsNothing);
      expect(fake.last('GET', '/api/production/reports').url.queryParameters['from'], isNotNull);
      await tester.tap(find.text('Até'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Até'), findsOneWidget);
    });

    testWidgets('empty list shows the empty text', (tester) async {
      final fake = _Fake()..reports = [];
      await _pump(tester, fake, (s) => ReportsScreen(session: s));
      expect(find.text('Nenhum apontamento'), findsOneWidget);
    });

    testWidgets('new report picks the order and the operation, then posts the report', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => ReportsScreen(session: s));
      await tester.tap(find.text('Novo apontamento'));
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/production/orders').url.queryParameters['open'], 'true');
      await tester.tap(find.text('12 · OF 12'));
      await tester.pumpAndSettle();
      expect(find.text('Operação · OF 12'), findsOneWidget);
      await tester.tap(find.text('20 · Trefilar · saldo 60'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Apontamento · OF 12 · operação 20 Trefilar'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-goodQuantity'))).controller!.text, '60');
      await tester.enterText(find.byKey(const ValueKey('field-goodQuantity')), '55');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/production/reports'));
      expect(b['orderId'], 7);
      expect(b['operationSequence'], 20);
      expect(b['goodQuantity'], 55);
      expect(b['scrapQuantity'], 0);
    });

    testWidgets('an order with a single internal operation skips the operation picker', (tester) async {
      final fake = _Fake()..ops = [_op(10, description: 'Perfilar'), _op(20, external: true)];
      await _pump(tester, fake, (s) => ReportsScreen(session: s));
      await tester.tap(find.text('Novo apontamento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12 · OF 12'));
      await tester.pumpAndSettle();
      expect(find.text('Operação · OF 12'), findsNothing);
      expect(find.textContaining('operação 10 Perfilar'), findsOneWidget);
    });

    testWidgets('an order with only outside operations explains why it cannot be reported', (tester) async {
      final fake = _Fake()..ops = [_op(20, external: true)];
      await _pump(tester, fake, (s) => ReportsScreen(session: s));
      await tester.tap(find.text('Novo apontamento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12 · OF 12'));
      await tester.pumpAndSettle();
      expect(find.text('OF 12 não tem operação interna para apontar'), findsOneWidget);
      expect(fake.has('POST', '/api/production/reports'), isFalse);
    });

    testWidgets('an operation without balance leaves the good quantity empty', (tester) async {
      final fake = _Fake()..ops = [_op(10, remaining: 0)];
      await _pump(tester, fake, (s) => ReportsScreen(session: s));
      await tester.tap(find.text('Novo apontamento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12 · OF 12'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-goodQuantity'))).controller!.text, '');
    });
  });

  group('remessas a terceiros', () {
    testWidgets('lists the shipments only in open by default and the filter can be cleared', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => OutsideProcessingScreen(session: s));
      expect(find.text('Galvano Sul'), findsOneWidget);
      expect(fake.last('GET', '/api/production/outside-shipments').url.queryParameters['open'], 'true');
      await tester.tap(find.text('Somente em aberto'));
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/production/outside-shipments').url.queryParameters.containsKey('open'), isFalse);
    });

    testWidgets('empty list shows the empty text', (tester) async {
      final fake = _Fake()..shipments = [];
      await _pump(tester, fake, (s) => OutsideProcessingScreen(session: s));
      expect(find.text('Nenhuma remessa a terceiros'), findsOneWidget);
    });

    testWidgets('a producer registers the return of an open shipment', (tester) async {
      final fake = _Fake();
      var changed = 0;
      await _pump(tester, fake, (s) => ShipmentsView(session: s, onChanged: () => changed++));
      await tester.tap(find.text('Galvano Sul'));
      await tester.pumpAndSettle();
      expect(find.text('Imprimir NF de remessa'), findsOneWidget);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Retorno de Galvano Sul · OF 12 op. 20'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-goodQuantity'))).controller!.text, '80');
      await tester.enterText(find.byKey(const ValueKey('field-serviceUnitPrice')), '2,5');
      await tester.enterText(find.byKey(const ValueKey('field-invoiceNumber')), 'R77');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/production/outside-shipments/5/returns'));
      expect(b['goodQuantity'], 80);
      expect(b['scrapQuantity'], 0);
      expect(b['serviceUnitPrice'], 2.5);
      expect(b['invoiceNumber'], 'R77');
      expect(changed, 1);
    });

    testWidgets('a reader opening a shipment goes to the order instead of the return form', (tester) async {
      final fake = _Fake()..role = 'Reader';
      await _pump(tester, fake, (s) => OutsideProcessingScreen(session: s));
      await tester.tap(find.text('Galvano Sul'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Retorno de'), findsNothing);
      expect(fake.has('GET', '/api/production/orders/7'), isTrue);
    });

    testWidgets('a fully returned shipment opens the order even for a producer', (tester) async {
      final fake = _Fake()..shipments = [{..._shipment, 'open': 0}];
      await _pump(tester, fake, (s) => OutsideProcessingScreen(session: s));
      await tester.tap(find.text('Galvano Sul'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Retorno de'), findsNothing);
      expect(fake.has('GET', '/api/production/orders/7'), isTrue);
    });

    testWidgets('inside an order the shipment tap does not navigate when nothing is open', (tester) async {
      final fake = _Fake()..shipments = [{..._shipment, 'open': 0}];
      await _pump(tester, fake, (s) => ShipmentsView(session: s, orderId: 7));
      expect(fake.last('GET', '/api/production/outside-shipments').url.queryParameters['orderId'], '7');
      await tester.tap(find.text('Galvano Sul'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(fake.has('GET', '/api/production/orders/7'), isFalse);
    });

    testWidgets('dismissing the action sheet does nothing', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => OutsideProcessingScreen(session: s));
      await tester.tap(find.text('Galvano Sul'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Imprimir NF de remessa'), findsNothing);
      expect(fake.log.any((r) => r.method == 'POST'), isFalse);
    });
  });

  group('planejamento', () {
    testWidgets('switching the grouping and the horizon reloads the load grid', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => PlanningScreen(session: s));
      expect(find.text('Máquina'), findsWidgets);
      expect(find.text('110 %'), findsOneWidget);
      expect(find.text('90 %'), findsOneWidget);
      expect(find.text('25 %'), findsOneWidget);
      expect(find.text('TREF-1'), findsOneWidget);
      var q = fake.last('GET', '/api/production/load').url.queryParameters;
      expect(q['groupBy'], 'machine');
      final days = DateTime.parse(q['to']!).difference(DateTime.parse(q['from']!)).inDays;
      expect(days, 8 * 7 - 1);
      await tester.tap(find.text('Centro de trabalho'));
      await tester.pumpAndSettle();
      q = fake.last('GET', '/api/production/load').url.queryParameters;
      expect(q['groupBy'], 'workCenter');
      await tester.tap(find.text('12 sem.'));
      await tester.pumpAndSettle();
      q = fake.last('GET', '/api/production/load').url.queryParameters;
      expect(DateTime.parse(q['to']!).difference(DateTime.parse(q['from']!)).inDays, 12 * 7 - 1);
      final before = fake.log.length;
      await tester.tap(find.byTooltip('Atualizar'));
      await tester.pumpAndSettle();
      expect(fake.log.length, before + 1);
    });

    testWidgets('empty load explains there is nothing scheduled', (tester) async {
      final fake = _Fake()..load = [];
      await _pump(tester, fake, (s) => PlanningScreen(session: s));
      expect(find.text('Sem carga programada no período'), findsOneWidget);
    });

    testWidgets('a load error is shown with retry', (tester) async {
      final fake = _Fake()..loadStatus = 500;
      await _pump(tester, fake, (s) => PlanningScreen(session: s));
      expect(find.textContaining('Carga indisponível'), findsOneWidget);
      fake.loadStatus = 200;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('110 %'), findsOneWidget);
    });

    testWidgets('a reader cannot reschedule', (tester) async {
      final fake = _Fake()..role = 'Reader';
      await _pump(tester, fake, (s) => PlanningScreen(session: s));
      expect(find.byKey(const ValueKey('schedule-all')), findsNothing);
    });

    testWidgets('cancelling the reschedule confirmation sends nothing; confirming shows the empty result', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => PlanningScreen(session: s));
      await tester.tap(find.byKey(const ValueKey('schedule-all')));
      await tester.pumpAndSettle();
      expect(find.text('Reprogramar todas as OFs abertas a partir de hoje?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/production/schedule'), isFalse);
      await tester.tap(find.byKey(const ValueKey('schedule-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(find.text('0 OF(s) programada(s)'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('0 OF(s) programada(s)'), findsNothing);
    });
  });

  testWidgets('showScheduleResult lists late orders with their warnings', (tester) async {
    final fake = _Fake();
    await _pump(
      tester,
      fake,
      (s) => Builder(
        builder: (c) => TextButton(
          onPressed: () => showScheduleResult(c, [
            {'reference': 'OF 12', 'dueDate': '2026-01-10', 'adjustedStart': '2026-10-27', 'adjustedEnd': '2026-10-29', 'late': true, 'warnings': ['Sem feriados', 'Capacidade']},
            {'reference': 'OF 13', 'dueDate': '2026-12-10', 'plannedStart': '2026-11-02', 'plannedEnd': '2026-11-03', 'late': false, 'warnings': []},
          ]),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('2 OF(s) programada(s) · 1 atrasada(s)'), findsOneWidget);
    expect(find.text('Sem feriados; Capacidade'), findsOneWidget);
    expect(find.text('Sim'), findsOneWidget);
    expect(find.text('OF 13'), findsOneWidget);
  });
}
