import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/production_orders.dart';
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

Map<String, dynamic> _op(int seq, {String description = 'Perfilar', bool external = false, int? supplierId}) => {
  'id': 70 + seq,
  'sequence': seq,
  'description': description,
  'machineId': 1,
  'machineCode': 'M$seq',
  'workCenterId': 1,
  'setupHours': 1,
  'piecesPerHour': 50,
  'operators': 1,
  'external': external,
  'supplierId': supplierId,
  'externalLeadDays': external ? 4 : null,
  'tolerance': '± 0,10',
  'measureStart': '14,00',
  'measureEnd': null,
  'plannedHours': 3,
  'plannedStart': '2026-10-27',
  'plannedEnd': '2026-10-28',
  'good': 0,
  'scrap': 0,
  'inTransit': 0,
  'overrunReleased': 0,
  'limit': 103,
  'remaining': 103,
};

Map<String, dynamic> _material(int id, {num remaining = 250, num issued = 0, num reserved = 0}) => {
  'id': id,
  'operationSequence': 10,
  'materialId': 4,
  'componentProductId': null,
  'code': 'BOB-$id',
  'description': 'Bobina $id',
  'unit': 'KG',
  'quantityPerUnit': 2.5,
  'required': remaining + issued,
  'issued': issued,
  'remaining': remaining,
  'reservationId': null,
  'reserved': reserved,
};

class _Fake {
  final log = <http.Request>[];
  var role = 'Production';
  var status = 'Created';
  String? statusReason;
  int? parentOrderId;
  String? costClosedAt;
  List<String> warnings = [];
  List<Map<String, dynamic>> children = [];
  List<Map<String, dynamic>> ops = [_op(10)];
  List<Map<String, dynamic>> materials = [_material(80)];
  List<Map<String, dynamic>> orders = [];
  int orderStatus = 200;
  String release = 'ok';
  List<dynamic> childResult = [];

  /// Extra fields of the order DTO (sales order, parent and previous references...).
  Map<String, dynamic> extra = {};

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);
  bool has(String method, String path) => log.any((r) => r.method == method && r.url.path == path);

  Map<String, dynamic> summary() => {
    'id': 7,
    'kind': 'Standard',
    'number': 12,
    'reference': 'OF 12',
    'productId': 3,
    'productCode': 'TB-50',
    'productName': 'Tubo 50x50',
    'customerId': null,
    'customerName': 'Incodiesel',
    'quantity': 100,
    'dueDate': '2026-01-10',
    'plannedStart': '2026-10-27',
    'plannedEnd': '2026-10-28',
    'adjustedStart': null,
    'adjustedEnd': '2026-11-02',
    'status': status,
    'parentOrderId': parentOrderId,
    'createdAt': '2026-10-20T10:00:00Z',
  };

  Map<String, dynamic> order() => {
    ...summary(),
    'productUnit': 'PC',
    'statusReason': statusReason,
    'previousOrderId': null,
    'bales': 4,
    'primaryTube': 'Rolo 14,00',
    'notes': 'Urgente',
    'createdBy': 'pcp',
    'releasedAt': null,
    'finishedAt': null,
    'closedAt': null,
    'closedBy': null,
    'costClosedAt': costClosedAt,
    'materialCost': null,
    'serviceCost': null,
    'unitCost': null,
    'good': 10,
    'scrap': 1,
    'received': 5,
    'receivable': 5,
    'workInProcess': 0,
    'operations': ops,
    'materials': materials,
    'children': children,
    'warnings': warnings,
    ...extra,
  };

  late final client = MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    final m = r.method;
    if (p == '/api/production/orders' && m == 'GET') return _json(_page(orders));
    if (p == '/api/production/orders' && m == 'POST') return _json({...order(), 'id': 7}, 201);
    if (p == '/api/products') {
      return _json(
        _page([
          {'id': 3, 'code': 'TB-50', 'name': 'Tubo 50x50'},
        ]),
      );
    }
    if (p == '/api/suppliers') {
      return _json(
        _page([
          {'id': 5, 'code': 'F5', 'name': 'Galvano Sul'},
        ]),
      );
    }
    if (p == '/api/production/orders/7' && m == 'GET') {
      if (orderStatus != 200) return _json({'title': 'Erro', 'detail': 'OF indisponível', 'status': orderStatus}, orderStatus);
      return _json(order());
    }
    if (p == '/api/production/orders/7' && m == 'PUT') return _json({...order(), 'quantity': 120});
    if (p == '/api/production/orders/7' && m == 'DELETE') return http.Response('', 204);
    if (p == '/api/production/orders/7/release') {
      if (release == 'ok') {
        status = 'Released';
        return _json({'order': order(), 'shortages': []});
      }
      if (release == 'other') return _json({'title': 'Erro', 'detail': 'Produto sem estrutura', 'status': 409}, 409);
      return _json({'title': 'Conflict', 'detail': 'Missing material: BOB-80', 'status': 409}, 409);
    }
    if (p == '/api/production/orders/7/availability') {
      return _json({
        'complete': false,
        'lines': [
          {'code': 'BOB-80', 'description': 'Bobina 80', 'unit': 'KG', 'remaining': 250, 'free': 200, 'onOrder': 0, 'shortage': 50},
          {'code': 'BOB-81', 'description': 'Bobina 81', 'unit': 'KG', 'remaining': 10, 'free': 10, 'onOrder': 0, 'shortage': 0},
        ],
      });
    }
    if (p == '/api/production/orders/7/child-orders') return _json(childResult);
    if (p == '/api/production/orders/7/schedule') {
      return _json([
        {'reference': 'OF 12', 'dueDate': '2026-01-10', 'plannedStart': '2026-10-27', 'plannedEnd': '2026-10-28', 'late': true, 'warnings': []},
      ]);
    }
    if (p == '/api/production/orders/7/stock-documents') {
      return _json([
        {'id': 50, 'type': 'Issue', 'date': '2026-10-21', 'movementCount': 2, 'createdBy': 'est', 'reversed': true},
      ]);
    }
    if (p == '/api/production/orders/7/reconciliation') {
      return _json({
        'planned': 100,
        'good': 10,
        'scrap': 1,
        'received': 5,
        'workInProcess': 0,
        'materialCost': 1500,
        'serviceCost': 200,
        'unitCost': 17,
        'lines': [
          {
            'code': 'BOB-80',
            'unit': 'KG',
            'planned': 250,
            'issued': 200,
            'inScrap': 0,
            'inFinishedGoods': 150,
            'balance': 50,
            'unitPrice': 6,
            'balanceValue': 300,
          },
        ],
      });
    }
    if (p == '/api/production/orders/7/process' && m == 'PUT') return _json(order());
    if (p == '/api/production/orders/7/receipts') return _json({'id': 1}, 201);
    if (p == '/api/production/orders/7/issues' || p == '/api/production/orders/7/material-returns') return _json({'id': 2}, 201);
    if (p.contains('/operations/') && p.endsWith('/outside-shipments')) {
      return _json({'id': 8, 'reference': 'OF 12', 'invoiceNumber': null}, 201);
    }
    if (p.contains('/operations/') && p.endsWith('/overrun-releases')) return _json({'id': 3}, 201);
    if (p.contains('/operations/') && (p.endsWith('/details') || p.endsWith('/outsource'))) return _json(order());
    if (p.startsWith('/api/production/orders/7/')) return _json(order());
    return _json(_page([]));
  });
}

Future<Session> _pump(WidgetTester tester, _Fake fake, Widget Function(Session s) screen) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2400);
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
      home: screen(session),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

/// Opens the order screen on top of a launcher so that popping it can be observed.
Future<Session> _pumpPushed(WidgetTester tester, _Fake fake) async {
  final s = await _pump(
    tester,
    fake,
    (s) => Builder(
      builder: (c) => Scaffold(
        body: TextButton(onPressed: () => openProductionOrder(c, s, 7), child: const Text('abrir')),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return s;
}

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const ValueKey('of-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Future<void> _confirmStep(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('confirm-step')));
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _pickLookup(WidgetTester tester, String label, String display) async {
  await tester.tap(find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(LookupPicker), matching: find.text(display)));
  await tester.pumpAndSettle();
}

Future<void> _opMenu(WidgetTester tester, int seq, String item) async {
  await tester.ensureVisible(find.byKey(ValueKey('op-menu-$seq')));
  await tester.tap(find.byKey(ValueKey('op-menu-$seq')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  group('lista de OFs', () {
    testWidgets('filters change the query and the producer can start a new OF', (tester) async {
      final fake = _Fake()
        ..orders = [
          {...(_Fake()..status = 'Released').summary(), 'dueDate': '2020-01-01'},
        ];
      await _pump(tester, fake, (s) => Scaffold(body: ProductionOrdersScreen(session: s)));
      expect(find.text('OF 12'), findsOneWidget);
      expect(find.text('Liberada'), findsOneWidget);
      expect(fake.last('GET', '/api/production/orders').url.queryParameters['open'], 'true');

      await tester.tap(find.text('Somente abertas'));
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/production/orders').url.queryParameters.containsKey('open'), isFalse);

      await tester.tap(find.byKey(const ValueKey('filter-Situação')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parada').last);
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/production/orders').url.queryParameters['status'], 'Stopped');

      await tester.tap(find.byKey(const ValueKey('filter-Tipo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPI (interna)').last);
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/production/orders').url.queryParameters['kind'], 'Internal');
    });

    testWidgets('initial status filter is applied and a reader has no new button', (tester) async {
      final fake = _Fake()..role = 'Reader';
      await _pump(
        tester,
        fake,
        (s) => Scaffold(
          body: ProductionOrdersScreen(session: s, initialStatus: 'Created'),
        ),
      );
      final q = fake.last('GET', '/api/production/orders').url.queryParameters;
      expect(q['status'], 'Created');
      expect(q.containsKey('open'), isFalse);
      expect(find.text('Nova Ordem de Fabricação'), findsNothing);
    });

    testWidgets('creating an OF posts the form and opens the new order', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => Scaffold(body: ProductionOrdersScreen(session: s)));
      await tester.tap(find.text('Nova Ordem de Fabricação'));
      await tester.pumpAndSettle();
      expect(find.text('Nova ordem de fabricação'), findsOneWidget);
      await _pickLookup(tester, 'Produto *', 'TB-50 · Tubo 50x50');
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '120');
      await tester.enterText(find.byKey(const ValueKey('field-dueDate')), '15/12/2026');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/production/orders'));
      expect(b['productId'], 3);
      expect(b['quantity'], 120);
      expect(b['dueDate'], '2026-12-15');
      expect(b['kind'], 'Standard');
      expect(find.text('OF 12 · TB-50'), findsOneWidget);
    });
  });

  group('situações e ações da OF', () {
    testWidgets('a load error is shown instead of the order', (tester) async {
      final fake = _Fake()..orderStatus = 500;
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      expect(find.text('Ordem de fabricação'), findsOneWidget);
      expect(find.textContaining('OF indisponível'), findsOneWidget);
    });

    testWidgets('summary shows warnings, the stop reason, the parent link and the children', (tester) async {
      final fake = _Fake()
        ..status = 'Stopped'
        ..statusReason = 'Falta de material'
        ..parentOrderId = 3
        ..warnings = ['Sem roteiro cadastrado']
        ..children = [
          {'id': 8, 'reference': 'OF 13', 'productCode': 'SUB-1', 'quantity': 10, 'dueDate': '2026-01-05', 'status': 'Created'},
        ];
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      expect(find.text('Sem roteiro cadastrado'), findsOneWidget);
      expect(find.text('Parada · Falta de material'), findsOneWidget);
      expect(find.text('OF pai'), findsOneWidget);
      expect(find.text('OF 13'), findsOneWidget);
      expect(find.byKey(const ValueKey('of-release')), findsNothing);
      await tester.tap(find.text('Retomar'));
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/production/orders/7/resume'), isTrue);
      expect(find.text('OF retomada'), findsOneWidget);
    });

    testWidgets('releasing without shortage reserves the material', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await tester.tap(find.byKey(const ValueKey('of-release')));
      await tester.pumpAndSettle();
      // Releasing says what it does first.
      expect(find.text('Liberar OF 12?'), findsOneWidget);
      expect(fake.has('POST', '/api/production/orders/7/release'), isFalse);
      await _confirmStep(tester);
      expect(fake.body(fake.last('POST', '/api/production/orders/7/release'))['force'], isFalse);
      expect(find.text('OF liberada e material reservado'), findsOneWidget);
      expect(find.byKey(const ValueKey('of-release')), findsNothing);
    });

    testWidgets('other release conflicts are shown as an error and the shortage dialog can be dismissed', (tester) async {
      final fake = _Fake()..release = 'other';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await tester.tap(find.byKey(const ValueKey('of-release')));
      await tester.pumpAndSettle();
      await _confirmStep(tester);
      expect(find.textContaining('Produto sem estrutura'), findsOneWidget);
      expect(find.text('Falta material'), findsNothing);

      fake.release = 'missing';
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(const ValueKey('of-release')));
      await tester.pumpAndSettle();
      await _confirmStep(tester);
      expect(find.text('Falta material'), findsOneWidget);
      expect(find.text('BOB-81'), findsNothing);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(fake.log.where((r) => r.url.path.endsWith('/release')).every((r) => fake.body(r)['force'] == false), isTrue);
    });

    testWidgets('a created OF can be edited, refreshed, split, scheduled and cancelled', (tester) async {
      final fake = _Fake()..childResult = [{}, {}];
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));

      await _menu(tester, 'Editar');
      expect(find.text('Editar OF 12'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '120');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('PUT', '/api/production/orders/7'))['quantity'], 120);

      await _menu(tester, 'Atualizar estrutura');
      expect(fake.has('POST', '/api/production/orders/7/refresh-structure'), isTrue);
      expect(find.text('Estrutura atualizada'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      await _menu(tester, 'Gerar OFs de subconjuntos');
      expect(find.text('Gerar OFs de subconjuntos?'), findsOneWidget);
      expect(fake.has('POST', '/api/production/orders/7/child-orders'), isFalse);
      await _confirmStep(tester);
      expect(find.text('2 OF(s) filha(s) gerada(s)'), findsOneWidget);
      fake.childResult = [];
      await tester.pump(const Duration(seconds: 5));
      await _menu(tester, 'Gerar OFs de subconjuntos');
      await _confirmStep(tester);
      expect(find.text('Nenhuma OF filha necessária'), findsOneWidget);

      await _menu(tester, 'Programar');
      expect(find.text('1 OF(s) programada(s) · 1 atrasada(s)'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      await _menu(tester, 'Cancelar');
      expect(find.text('Cancelar OF 12'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('cancel-reason')), 'Cliente desistiu');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancel-confirm')));
      await tester.pumpAndSettle();
      var b = fake.body(fake.last('POST', '/api/production/orders/7/cancel'));
      expect(b['reason'], 'Cliente desistiu');
      expect(b['technical'], isFalse);

      // The technical kind is a switch in the same dialog, not a second menu entry.
      await tester.pump(const Duration(seconds: 5));
      await _menu(tester, 'Cancelar');
      expect(find.text('Cancelamento técnico'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('cancel-reason')), 'Erro de cadastro');
      await tester.tap(find.byKey(const ValueKey('cancel-technical')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancel-confirm')));
      await tester.pumpAndSettle();
      b = fake.body(fake.last('POST', '/api/production/orders/7/cancel'));
      expect(b['technical'], isTrue);
    });

    testWidgets('cancelling needs a reason', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _menu(tester, 'Cancelar');
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('cancel-confirm'))).onPressed, isNull);
      expect(fake.has('POST', '/api/production/orders/7/cancel'), isFalse);
      expect(find.text('Cancelar OF 12'), findsOneWidget);
    });

    testWidgets('deleting a created OF confirms, deletes and goes back', (tester) async {
      final fake = _Fake();
      await _pumpPushed(tester, fake);
      await _menu(tester, 'Excluir');
      expect(find.text('Excluir OF 12?'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(fake.has('DELETE', '/api/production/orders/7'), isTrue);
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('a running OF can be stopped, receive finished goods and be finished', (tester) async {
      final fake = _Fake()..status = 'InProduction';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      expect(find.byKey(const ValueKey('of-release')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('of-receive')));
      await tester.pumpAndSettle();
      expect(find.text('Entrada de produto acabado · OF 12'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-quantity'))).controller!.text, '5');
      await tester.enterText(find.byKey(const ValueKey('field-lotCode')), 'L-1');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/production/orders/7/receipts'));
      expect(b['quantity'], 5);
      expect(b['lotCode'], 'L-1');

      await _menu(tester, 'Parar');
      await tester.enterText(find.byType(TextField), 'Quebra de máquina');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('POST', '/api/production/orders/7/stop'))['reason'], 'Quebra de máquina');

      // Let the earlier snackbars go before the next message is checked.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      await _menu(tester, 'Finalizar');
      // The balance still open on the operations is named before the OF is finished.
      expect(find.text('Finalizar OF 12?'), findsOneWidget);
      expect(find.textContaining('saldo nas operações'), findsOneWidget);
      expect(fake.has('POST', '/api/production/orders/7/finish'), isFalse);
      await _confirmStep(tester);
      expect(fake.has('POST', '/api/production/orders/7/finish'), isTrue);
      expect(find.text('OF finalizada'), findsOneWidget);
    });

    testWidgets('a finished OF can be reopened or closed', (tester) async {
      final fake = _Fake()..status = 'Finished';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _menu(tester, 'Reabrir');
      expect(fake.has('POST', '/api/production/orders/7/reopen'), isTrue);
      await tester.pump(const Duration(seconds: 5));
      await _menu(tester, 'Encerrar');
      expect(fake.has('POST', '/api/production/orders/7/close'), isFalse);
      await _confirmStep(tester);
      expect(fake.has('POST', '/api/production/orders/7/close'), isTrue);
      expect(find.text('OF encerrada'), findsOneWidget);
    });

    testWidgets('a closed OF without closed cost offers to close the cost; the cost tab shows the reconciliation', (tester) async {
      final fake = _Fake()..status = 'Closed';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Custo');
      expect(find.text('Custo (prévia)'), findsOneWidget);
      expect(find.text('Balanço de material'), findsOneWidget);
      expect(find.text('BOB-80'), findsOneWidget);
      await _menu(tester, 'Fechar custo');
      expect(fake.has('POST', '/api/production/orders/7/close-cost'), isFalse);
      await _confirmStep(tester);
      expect(fake.has('POST', '/api/production/orders/7/close-cost'), isTrue);
      expect(find.text('Custo fechado'), findsWidgets);
    });

    testWidgets('a closed OF with closed cost has no menu entry for it', (tester) async {
      final fake = _Fake()
        ..status = 'Closed'
        ..costClosedAt = '2026-10-30T10:00:00Z';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      expect(find.byKey(const ValueKey('of-menu')), findsNothing);
      await _tab(tester, 'Custo');
      expect(find.textContaining('Custo fechado em'), findsOneWidget);
    });
  });

  group('operações', () {
    testWidgets('the process dialog removes only new rows and needs a description for every row', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Operações');
      await tester.tap(find.byKey(const ValueKey('op-edit-process')));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('process-del-0'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('process-add')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('process-save'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('process-del-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('process-desc-1')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('process-save'))).onPressed, isNotNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(fake.has('PUT', '/api/production/orders/7/process'), isFalse);
    });

    testWidgets('operation menu: tolerance and measures, extra quantity and outside processing', (tester) async {
      final fake = _Fake()..status = 'Released';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Operações');
      expect(find.text('14,00'), findsWidgets);

      await _opMenu(tester, 10, 'Tolerância e medidas');
      expect(find.text('Tolerância e medidas · operação 10'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-tolerance'))).controller!.text, '± 0,10');
      await tester.enterText(find.byKey(const ValueKey('field-measureEnd')), '12,00');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      var b = fake.body(fake.last('PUT', '/api/production/orders/7/operations/10/details'));
      expect(b['measureEnd'], '12,00');
      expect(b['measureStart'], '14,00');

      await _opMenu(tester, 10, 'Liberar excedente');
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '20');
      await tester.enterText(find.byKey(const ValueKey('field-justification')), 'Refugo acima do previsto');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      b = fake.body(fake.last('POST', '/api/production/orders/7/operations/10/overrun-releases'));
      expect(b['quantity'], 20);
      expect(b['justification'], 'Refugo acima do previsto');

      await _opMenu(tester, 10, 'Beneficiamento externo');
      await _pickLookup(tester, 'Fornecedor *', 'F5 · Galvano Sul');
      await tester.enterText(find.byKey(const ValueKey('field-leadDays')), '4');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      b = fake.body(fake.last('PUT', '/api/production/orders/7/operations/10/outsource'));
      expect(b['supplierId'], 5);
      expect(b['leadDays'], 4);
    });

    testWidgets('an outside operation can be sent to the supplier or brought back inside', (tester) async {
      final fake = _Fake()
        ..status = 'Released'
        ..ops = [_op(10), _op(20, description: 'Galvanizar', external: true, supplierId: 5)];
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Operações');
      expect(find.text('Galvanizar (externo)'), findsOneWidget);
      expect(find.byKey(const ValueKey('op-send-10')), findsNothing);
      expect(find.byKey(const ValueKey('op-report-20')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('op-send-20')));
      await tester.tap(find.byKey(const ValueKey('op-send-20')));
      await tester.pumpAndSettle();
      expect(find.text('Remessa para beneficiamento · operação 20'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-quantity'))).controller!.text, '103');
      await tester.enterText(find.byKey(const ValueKey('field-unitValue')), '1,5');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/production/orders/7/operations/20/outside-shipments'));
      expect(b['quantity'], 103);
      expect(b['unitValue'], 1.5);
      // The NF print dialog opens after the shipment; leave it.
      if (find.text('Cancelar').evaluate().isNotEmpty) {
        await tester.tap(find.text('Cancelar').last);
        await tester.pumpAndSettle();
      }

      await _opMenu(tester, 20, 'Voltar para interno');
      expect(find.text('Voltar a operação 20 para produção interna?'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(fake.has('DELETE', '/api/production/orders/7/operations/20/outsource'), isTrue);
    });

    testWidgets('a finished OF has no operation actions', (tester) async {
      final fake = _Fake()..status = 'Finished';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Operações');
      expect(find.byKey(const ValueKey('op-menu-10')), findsNothing);
      expect(find.byKey(const ValueKey('op-edit-process')), findsNothing);
    });
  });

  group('vínculos e avisos', () {
    testWidgets('the summary names the sales order, the customer PO and the previous OF; the link menu leads to them', (tester) async {
      final fake = _Fake()
        ..parentOrderId = 3
        ..extra = {
          'salesOrderId': 9,
          'salesOrderReference': 'PV 9',
          'customerPo': 'PC-4455',
          'parentOrderReference': 'OF 3',
          'previousOrderId': 4,
          'previousOrderReference': 'OF 4',
        };
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      expect(find.text('PV 9'), findsOneWidget);
      expect(find.text('PC-4455'), findsOneWidget);
      expect(find.text('OF anterior OF 4'), findsOneWidget);
      expect(find.text('OF pai OF 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('related-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Pedido de venda PV 9'), findsOneWidget);
      expect(find.text('OF pai OF 3'), findsWidgets);
      expect(find.text('OF anterior OF 4'), findsWidgets);
    });

    testWidgets('a stopped OF shows its reason in a banner', (tester) async {
      final fake = _Fake()
        ..status = 'Stopped'
        ..statusReason = 'Quebra de máquina';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      expect(find.byKey(const ValueKey('of-status-reason')), findsOneWidget);
      expect(find.text('Parada: Quebra de máquina'), findsOneWidget);
    });

    testWidgets('receiving finished goods offers to open the stock document it created', (tester) async {
      final fake = _Fake()..status = 'InProduction';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await tester.tap(find.byKey(const ValueKey('of-receive')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Entrada de produto acabado lançada'), findsOneWidget);
      expect(find.text('Abrir movimentação'), findsOneWidget);
    });

    testWidgets('generating subassemblies moves to the summary where they are listed', (tester) async {
      final fake = _Fake()..childResult = [{}];
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Materiais');
      await _menu(tester, 'Gerar OFs de subconjuntos');
      await _confirmStep(tester);
      expect(find.text('Ordem'), findsOneWidget);
    });

    testWidgets('a user who moves material but cannot report sees a disabled Apontar with the reason', (tester) async {
      final fake = _Fake()
        ..status = 'Released'
        ..role = 'Stock';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Operações');
      expect(find.byKey(const ValueKey('op-menu-10')), findsNothing);
      final report = find.byKey(const ValueKey('op-report-10'));
      expect(report, findsOneWidget);
      expect(tester.widget<IconButton>(report).onPressed, isNull);
      expect(tester.widget<IconButton>(report).tooltip, 'Sem permissão para apontar');
    });

    testWidgets('the process dialog moves rows, numbers them by position and asks before dropping edits', (tester) async {
      final fake = _Fake()..ops = [_op(10, description: 'Perfilar'), _op(20, description: 'Cortar')];
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Operações');
      await tester.tap(find.byKey(const ValueKey('op-edit-process')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('process-desc-0'))).controller!.text, 'Perfilar');
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('process-up-0'))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('process-del-0'))).tooltip, contains('não pode ser removida'));
      await tester.tap(find.byKey(const ValueKey('process-down-0')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('process-desc-0'))).controller!.text, 'Cortar');
      // An edit was made: Cancelar asks first.
      await tester.tap(find.byKey(const ValueKey('process-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('process-desc-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('process-save')));
      await tester.pumpAndSettle();
      final lines = (fake.body(fake.last('PUT', '/api/production/orders/7/process'))['operations'] as List).cast<Map<String, dynamic>>();
      expect(lines.map((l) => l['description']), ['Cortar', 'Perfilar']);
      expect(lines.map((l) => l['sequence']), [20, 10]);
    });

    testWidgets('the new OF form folds the rare fields', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => Scaffold(body: ProductionOrdersScreen(session: s)));
      await tester.tap(find.text('Nova Ordem de Fabricação'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-quantity')), findsOneWidget);
      expect(find.byKey(const ValueKey('field-primaryTube')), findsNothing);
      expect(find.byKey(const ValueKey('field-notes')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('form-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-primaryTube')), findsOneWidget);
    });

    testWidgets('cancelling the new OF form does not reload the list', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => Scaffold(body: ProductionOrdersScreen(session: s)));
      final loads = fake.log.where((r) => r.method == 'GET' && r.url.path == '/api/production/orders').length;
      await tester.tap(find.text('Nova Ordem de Fabricação'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(fake.log.where((r) => r.method == 'GET' && r.url.path == '/api/production/orders').length, loads);
    });
  });

  group('materiais', () {
    testWidgets('requisitar saldo asks for confirmation and posts the date', (tester) async {
      final fake = _Fake()
        ..status = 'Released'
        ..role = 'Stock';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Materiais');
      await tester.tap(find.byKey(const ValueKey('issue-all')));
      await tester.pumpAndSettle();
      expect(find.text('Requisitar todo o saldo dos materiais para OF 12?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/production/orders/7/issues'), isFalse);
      await tester.tap(find.byKey(const ValueKey('issue-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('POST', '/api/production/orders/7/issues')).containsKey('date'), isTrue);
      expect(find.text('Material requisitado'), findsOneWidget);
    });

    testWidgets('returning issued material posts a return line; lines without issue cannot be returned', (tester) async {
      final fake = _Fake()
        ..status = 'Released'
        ..role = 'Stock'
        ..materials = [_material(80), _material(81, remaining: 0, issued: 50)];
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Materiais');
      expect(find.text('Movimentações de estoque'), findsOneWidget);
      expect(find.text('Requisição (consumo)'), findsOneWidget);
      expect(find.text('Sim'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('issue-81'))).onPressed, isNull);
      final returns = find.widgetWithIcon(IconButton, Icons.undo);
      expect(tester.widget<IconButton>(returns.first).onPressed, isNull);
      await tester.tap(returns.last);
      await tester.pumpAndSettle();
      expect(find.text('Devolver BOB-81'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '20');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/production/orders/7/material-returns'));
      expect(b['lines'], [
        {'materialLineId': 81, 'quantity': 20, 'lotId': null},
      ]);
    });

    testWidgets('a created OF cannot issue or return material', (tester) async {
      final fake = _Fake()..role = 'Stock';
      await _pump(tester, fake, (s) => ProductionOrderScreen(session: s, id: 7));
      await _tab(tester, 'Materiais');
      expect(find.byKey(const ValueKey('issue-all')), findsNothing);
      expect(find.byKey(const ValueKey('issue-80')), findsNothing);
      expect(find.byTooltip('Devolver ao estoque'), findsNothing);
    });
  });
}
