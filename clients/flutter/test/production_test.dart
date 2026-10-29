import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/screens/production_floor.dart';
import 'package:ebt_engenharia/screens/production_orders.dart';
import 'package:ebt_engenharia/screens/shell.dart';
import 'package:ebt_engenharia/session.dart';
import 'role_permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nav.dart';

http.Response json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> page(List<Map<String, dynamic>> items) => {'items': items, 'total': items.length, 'skip': 0, 'take': 50};

class Fake {
  final log = <http.Request>[];
  String role = 'Production';
  String status = 'Created';

  Map<String, dynamic> get summary => {
    'id': 7,
    'kind': 'Standard',
    'number': 12,
    'reference': 'OF 12',
    'productId': 3,
    'productCode': 'TB-50',
    'productName': 'Tubo 50x50',
    'customerId': null,
    'customerName': null,
    'quantity': 100,
    'dueDate': '2026-01-10',
    'plannedStart': null,
    'plannedEnd': null,
    'adjustedStart': null,
    'adjustedEnd': null,
    'status': status,
    'parentOrderId': null,
    'createdAt': '2026-10-20T10:00:00Z',
  };

  Map<String, dynamic> order() => {
    ...summary,
    'productUnit': 'PC',
    'statusReason': null,
    'previousOrderId': null,
    'bales': null,
    'notes': null,
    'createdBy': 'pcp',
    'releasedAt': null,
    'finishedAt': null,
    'closedAt': null,
    'closedBy': null,
    'costClosedAt': null,
    'materialCost': null,
    'serviceCost': null,
    'unitCost': null,
    'good': 0,
    'scrap': 0,
    'received': 0,
    'receivable': 0,
    'workInProcess': 0,
    'operations': [
      {
        'id': 70,
        'sequence': 10,
        'description': 'Perfilar',
        'machineId': 1,
        'machineCode': 'PERF-1',
        'workCenterId': 1,
        'setupHours': 1,
        'piecesPerHour': 50,
        'operators': 1,
        'external': false,
        'supplierId': null,
        'externalLeadDays': null,
        'plannedHours': 3,
        'plannedStart': null,
        'plannedEnd': null,
        'good': 0,
        'scrap': 0,
        'inTransit': 0,
        'overrunReleased': 0,
        'limit': 103,
        'remaining': 103,
      },
    ],
    'materials': [
      {
        'id': 80,
        'operationSequence': 10,
        'materialId': 4,
        'componentProductId': null,
        'code': 'BOB-15',
        'description': 'Bobina 1,5mm',
        'unit': 'KG',
        'quantityPerUnit': 2.5,
        'required': 250,
        'issued': 0,
        'remaining': 250,
        'reservationId': null,
        'reserved': 0,
      },
    ],
    'children': [],
    'warnings': [],
  };

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);

  MockClient get client => MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    final m = r.method;
    if (p == '/api/production/orders' && m == 'GET') return json(page([summary]));
    if (p == '/api/production/orders/7') return json(order());
    if (p == '/api/production/orders/7/release') {
      if (body(r)['force'] != true) return json({'title': 'Conflict', 'detail': 'Missing material: BOB-15 short by 50 KG', 'status': 409}, 409);
      status = 'Released';
      return json({'order': order(), 'shortages': []});
    }
    if (p == '/api/production/orders/7/availability') {
      return json({
        'complete': false,
        'lines': [
          {
            'materialLineId': 80,
            'materialId': 4,
            'productId': null,
            'code': 'BOB-15',
            'description': 'Bobina 1,5mm',
            'unit': 'KG',
            'required': 250,
            'issued': 0,
            'remaining': 250,
            'reservedForOrder': 0,
            'free': 200,
            'onOrder': 1000,
            'shortage': 50,
          },
        ],
      });
    }
    if (p == '/api/production/orders/7/issues') return json({'id': 50}, 201);
    if (p == '/api/production/orders/7/stock-documents') return json([]);
    if (p == '/api/production/orders/7/reconciliation') {
      return json({
        'orderId': 7,
        'reference': 'OF 12',
        'planned': 100,
        'good': 0,
        'scrap': 0,
        'received': 0,
        'workInProcess': 0,
        'materialCost': 0,
        'serviceCost': 0,
        'unitCost': null,
        'lines': [],
      });
    }
    if (p == '/api/production/reports' && m == 'POST') return json({'id': 1}, 201);
    if (p == '/api/production/reports') return json(page([]));
    if (p == '/api/production/outside-shipments') return json([]);
    if (p == '/api/production/schedule') {
      return json([
        {
          'orderId': 7,
          'reference': 'OF 12',
          'dueDate': '2026-01-10',
          'plannedStart': '2026-10-27',
          'plannedEnd': '2026-10-28',
          'adjustedStart': null,
          'adjustedEnd': null,
          'late': true,
          'operations': [],
          'warnings': ['Sem feriados'],
        },
      ]);
    }
    if (p == '/api/production/load') {
      return json([
        {'id': 1, 'code': 'PERF-1', 'weekStart': '2026-10-26', 'hours': 44, 'capacity': 40, 'loadPercent': 110, 'operations': 3},
      ]);
    }
    return json(page([]));
  });
}

Future<Session> pumpScreen(WidgetTester tester, Fake fake, Widget Function(Session s) screen) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session =
      Session(
          api: ApiClient(baseUrl: 'http://api.test', client: fake.client, token: 'tok'),
        )
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
  test('production role permissions; times are parsed', () {
    final s = Session(api: ApiClient(baseUrl: 'http://x'))..role = 'Production'..permissions = rolePermissions['Production']!;
    expect(s.canProduce, isTrue);
    expect(s.canMoveProduction, isTrue);
    expect(parseTime('7:30'), '07:30:00');
    expect(parseTime('1400'), '14:00:00');
    expect(parseTime('25:00'), isNull);
    expect(fmtTime('06:00:00'), '06:00');
    expect(productionLate({'status': 'Released', 'dueDate': '2020-01-01'}), isTrue);
    expect(productionLate({'status': 'Closed', 'dueDate': '2020-01-01'}), isFalse);
  });

  testWidgets('release with missing material shows the shortage and forces the release', (tester) async {
    final fake = Fake();
    await pumpScreen(tester, fake, (s) => Shell(session: s));
    await openScreen(tester, 'PCP', 'production-orders');
    await tester.tap(find.text('OF 12'));
    await tester.pumpAndSettle();
    expect(find.text('OF 12 · TB-50'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('of-release')));
    await tester.pumpAndSettle();
    expect(find.text('Falta material'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('release-force')));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/production/orders/7/release'))['force'], isTrue);
    expect(find.byKey(const ValueKey('of-release')), findsNothing);
    expect(find.text('Entrada PA'), findsOneWidget);
  });

  testWidgets('shop-floor report from the operation tab', (tester) async {
    final fake = Fake()..status = 'Released';
    await pumpScreen(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
    await tester.tap(find.text('Operações'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('op-report-10')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-goodQuantity')), '40');
    await tester.enterText(find.byKey(const ValueKey('field-startTime')), '7:00');
    await tester.enterText(find.byKey(const ValueKey('field-endTime')), '11:30');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final b = fake.body(fake.last('POST', '/api/production/reports'));
    expect(b['orderId'], 7);
    expect(b['operationSequence'], 10);
    expect(b['goodQuantity'], 40);
    expect(b['scrapQuantity'], 0);
    expect(b['startTime'], '07:00:00');
    expect(b['endTime'], '11:30:00');
  });

  testWidgets('stock user issues the remaining material but cannot release', (tester) async {
    final fake = Fake()
      ..role = 'Stock'
      ..status = 'Released';
    await pumpScreen(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
    expect(find.byKey(const ValueKey('of-menu')), findsNothing);
    await tester.tap(find.text('Materiais'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('issue-80')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final b = fake.body(fake.last('POST', '/api/production/orders/7/issues'));
    expect(b['lines'], [
      {'materialLineId': 80, 'quantity': 250, 'lotId': null},
    ]);
  });

  testWidgets('reader sees PCP read-only', (tester) async {
    final fake = Fake()..role = 'Reader';
    await pumpScreen(tester, fake, (s) => Shell(session: s));
    await openScreen(tester, 'PCP', 'production-orders');
    expect(find.text('Nova Ordem de Fabricação'), findsNothing);
    await tester.tap(find.text('OF 12'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('of-release')), findsNothing);
    expect(find.byKey(const ValueKey('of-menu')), findsNothing);
    await tester.tap(find.text('Operações'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('op-report-10')), findsNothing);
  });

  testWidgets('planning shows the weekly load and reschedules all orders', (tester) async {
    final fake = Fake();
    await pumpScreen(tester, fake, (s) => PlanningScreen(session: s));
    expect(find.text('PERF-1'), findsOneWidget);
    expect(find.text('110 %'), findsOneWidget);
    expect(fake.last('GET', '/api/production/load').url.queryParameters['groupBy'], 'machine');
    await tester.tap(find.byKey(const ValueKey('schedule-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(find.text('1 OF(s) programada(s) · 1 atrasada(s)'), findsOneWidget);
  });
}
