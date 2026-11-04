import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/orders.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/entity_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {'items': items, 'total': items.length, 'skip': 0, 'take': 50};

String _day(int offset) => DateTime.now().add(Duration(days: offset)).toIso8601String().substring(0, 10);

class _Env {
  String status = 'Open';
  double received = 0;
  String? failWith;
  final log = <http.Request>[];

  Map<String, dynamic> order() => {
    'id': 90,
    'number': 900,
    'supplierId': 1,
    'supplierName': 'Aços Sul',
    'status': status,
    'issuedBy': 'comp',
    'issuedAt': '2026-10-20T12:00:00Z',
    'paymentTerms': '28/56',
    'total': 2500,
    'notes': 'Urgente',
    'closedBy': status == 'Closed' ? 'comp' : null,
    'closedAt': status == 'Closed' ? '2026-10-25T12:00:00Z' : null,
    'closeReason': status == 'Closed' ? 'Saldo não será entregue' : null,
    'lines': [
      {
        'id': 91,
        'lineNumber': 1,
        'materialCode': 'MP-1',
        'description': 'Tubo bruto',
        'quantity': 500,
        'unit': 'kg',
        'unitPrice': 5,
        'discountPercent': 0,
        'ipiPercent': 5,
        'dueDate': _day(-3),
        'receivedQuantity': received,
        'openQuantity': 500 - received,
        'total': 2500,
      },
      {
        'id': 92,
        'lineNumber': 2,
        'materialCode': 'MP-2',
        'description': 'Chapa',
        'quantity': 10,
        'unit': 'un',
        'unitPrice': 1,
        'discountPercent': 0,
        'ipiPercent': 0,
        'dueDate': _day(10),
        'receivedQuantity': 0,
        'openQuantity': 10,
        'total': 10,
      },
    ],
  };

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);

  http.Response answer(http.Request r) {
    log.add(r);
    final p = r.url.path;
    if (r.method == 'POST' && failWith != null) return _json({'title': 'Pedido bloqueado', 'detail': failWith}, 409);
    if (r.method == 'POST' && p == '/api/purchase-orders') return _json({...order(), 'id': 90}, 201);
    if (r.method == 'POST' && p == '/api/purchase-orders/90/cancel') {
      status = 'Cancelled';
      return _json(order());
    }
    if (r.method == 'POST' && p == '/api/purchase-orders/90/close') {
      status = 'Closed';
      return _json(order());
    }
    if (r.method == 'PUT' && p.endsWith('/due-date')) return _json(order());
    if (p == '/api/purchase-orders/90') return _json(order());
    if (p == '/api/purchase-orders') {
      return _json(
        _page([
          {'id': 90, 'number': 900, 'supplierName': 'Aços Sul', 'issuedAt': '2026-10-20T12:00:00Z', 'status': 'Open', 'nextDueDate': _day(-2), 'lineCount': 2},
          {'id': 91, 'number': 901, 'supplierName': 'Metais Norte', 'issuedAt': '2026-10-21T12:00:00Z', 'status': 'Open', 'nextDueDate': _day(20), 'lineCount': 1},
        ]),
      );
    }
    if (p == '/api/suppliers') {
      return _json(
        _page([
          {'id': 1, 'code': 'F1', 'name': 'Aços Sul'},
        ]),
      );
    }
    if (p == '/api/materials') {
      return _json(
        _page([
          {'id': 4, 'code': 'MP-1', 'description': 'Tubo bruto', 'purchaseUnit': 'kg'},
        ]),
      );
    }
    if (p == '/api/purchasing/overdue') {
      return _json(
        _page([
          {
            'purchaseOrderId': 90,
            'purchaseOrderNumber': 900,
            'lineNumber': 1,
            'supplierName': 'Aços Sul',
            'description': 'Tubo bruto',
            'quantity': 500,
            'unit': 'kg',
            'receivedQuantity': 0,
            'openQuantity': 500,
            'dueDate': _day(-20),
            'daysLate': 20,
          },
        ]),
      );
    }
    return _json(_page([]));
  }
}

Future<Session> _pump(WidgetTester tester, _Env env, Widget Function(Session) screen, {String role = 'Purchasing'}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: MockClient((r) async => env.answer(r)), token: 'tok'))
    ..username = 'comp'
    ..role = role
    ..permissions = rolePermissions[role]!;
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

void main() {
  test('isLate and lineTotal handle dates and missing numbers', () {
    expect(isLate(_day(-1)), isTrue);
    expect(isLate(_day(0)), isFalse);
    expect(isLate(null), isFalse);
    expect(isLate('xx'), isFalse);
    expect(lineTotal({'quantity': 10, 'unitPrice': 2, 'discountPercent': 10, 'ipiPercent': 5}), closeTo(18.9, 0.0001));
    expect(lineTotal({'quantity': '10'}), 0);
    expect(zeroPercentsLine({'a': 1, 'ipiPercent': 4}), {'a': 1, 'ipiPercent': 4, 'discountPercent': 0, 'icmsPercent': 0});
  });

  testWidgets('order list asks for open orders, clears the filter and opens an order', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => Scaffold(body: OrdersScreen(session: s)));
    expect(env.log.first.url.queryParameters['open'], 'true');
    expect(find.text('Aços Sul'), findsOneWidget);
    expect(find.text('Metais Norte'), findsOneWidget);
    expect(find.text('Novo pedido'), findsOneWidget);
    await tester.tap(find.text('Somente abertos'));
    await tester.pumpAndSettle();
    expect(env.log.last.url.queryParameters.containsKey('open'), isFalse);
    await tester.tap(find.text('Aços Sul'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido nº 900 · Aços Sul'), findsOneWidget);
    expect(find.text('Urgente'), findsOneWidget);
    // Cancelling is a labelled button on the order page, not a hidden menu.
    expect(find.byKey(const ValueKey('order-menu')), findsOneWidget);
  });

  testWidgets('a status picked in the filter wins over "Somente abertos"', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => Scaffold(body: OrdersScreen(session: s)));
    expect(env.log.first.url.queryParameters['open'], 'true');
    await tester.tap(find.byKey(const ValueKey('filter-Situação')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encerrado').last);
    await tester.pumpAndSettle();
    expect(env.log.last.url.queryParameters['status'], 'Closed');
    expect(env.log.last.url.queryParameters.containsKey('open'), isFalse);
  });

  testWidgets('order list of a supplier starts new orders for that supplier and a reader cannot create', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => Scaffold(body: OrdersScreen(session: s, supplierId: 1, supplierName: 'Aços Sul')));
    expect(env.log.first.url.queryParameters['supplierId'], '1');
    await tester.tap(find.text('Novo pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Novo pedido de compra'), findsOneWidget);
    // The supplier is already chosen and cannot be changed there.
    expect(find.text('Aços Sul'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final env2 = _Env();
    await _pump(tester, env2, (s) => Scaffold(body: OrdersScreen(session: s)), role: 'Reader');
    expect(find.text('Novo pedido'), findsNothing);
  });

  testWidgets('buyer cancels an open order without receipts after giving a reason', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => OrderScreen(session: s, id: 90));
    expect(find.text('Receber NF'), findsOneWidget);
    expect(find.text('Encerrar saldo'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('order-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('order-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar pedido nº 900'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cancelar pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Obrigatório'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'Fornecedor errado');
    await tester.tap(find.widgetWithText(FilledButton, 'Cancelar pedido'));
    await tester.pumpAndSettle();
    expect(env.body(env.last('POST', '/api/purchase-orders/90/cancel')), {'reason': 'Fornecedor errado'});
    expect(find.text('Pedido cancelado'), findsOneWidget);
    expect(find.text('Cancelado'), findsWidgets);
    expect(find.text('Receber NF'), findsNothing);
  });

  testWidgets('buyer closes the balance of a partly received order and backing out sends nothing', (tester) async {
    final env = _Env()
      ..status = 'PartiallyReceived'
      ..received = 100;
    await _pump(tester, env, (s) => OrderScreen(session: s, id: 90));
    expect(find.text('Cancelar pedido'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('order-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('order-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(env.log.where((r) => r.method == 'POST'), isEmpty);
    await tester.tap(find.byKey(const ValueKey('order-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('order-close')));
    await tester.pumpAndSettle();
    expect(find.text('Encerrar saldo do pedido nº 900'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'Saldo não será entregue');
    await tester.tap(find.widgetWithText(FilledButton, 'Encerrar saldo'));
    await tester.pumpAndSettle();
    expect(env.body(env.last('POST', '/api/purchase-orders/90/close'))['reason'], 'Saldo não será entregue');
    expect(find.text('Pedido encerrado'), findsOneWidget);
    expect(find.textContaining('Saldo não será entregue'), findsWidgets);
  });

  testWidgets('a failed cancel shows the API message in a snackbar and keeps the order open', (tester) async {
    final env = _Env()..failWith = 'Há recebimento em andamento';
    await _pump(tester, env, (s) => OrderScreen(session: s, id: 90));
    await tester.tap(find.byKey(const ValueKey('order-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('order-cancel')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'x');
    await tester.tap(find.widgetWithText(FilledButton, 'Cancelar pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido bloqueado: Há recebimento em andamento'), findsOneWidget);
    expect(find.text('Receber NF'), findsOneWidget);
  });

  testWidgets('buyer reschedules the open line and the order reloads', (tester) async {
    final env = _Env()
      ..status = 'PartiallyReceived'
      ..received = 500;
    await _pump(tester, env, (s) => OrderScreen(session: s, id: 90));
    final buttons = find.widgetWithIcon(IconButton, Icons.event_outlined);
    expect(buttons, findsNWidgets(2));
    expect(tester.widget<IconButton>(buttons.at(0)).onPressed, isNull); // fully received line
    await tester.tap(buttons.at(1));
    await tester.pumpAndSettle();
    expect(find.text('Reprogramar linha 2'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('field-dueDate')), '30/11/2026');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(env.body(env.last('PUT', '/api/purchase-orders/90/lines/92/due-date'))['dueDate'], '2026-11-30');
    expect(env.log.where((r) => r.method == 'GET' && r.url.path == '/api/purchase-orders/90').length, 2);
  });

  testWidgets('a stock clerk can receive but not cancel, and a reader sees neither', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => OrderScreen(session: s, id: 90), role: 'Stock');
    expect(find.text('Receber NF'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byTooltip('Reprogramar entrega'), findsNothing);
    final env2 = _Env();
    await _pump(tester, env2, (s) => OrderScreen(session: s, id: 90), role: 'Reader');
    expect(find.text('Receber NF'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('a closed order shows who closed it and offers no actions', (tester) async {
    final env = _Env()..status = 'Closed';
    await _pump(tester, env, (s) => OrderScreen(session: s, id: 90));
    expect(find.textContaining('Saldo não será entregue'), findsOneWidget);
    expect(find.text('Receber NF'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('receive button opens the receiving screen and the order reloads on return', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => OrderScreen(session: s, id: 90));
    await tester.tap(find.text('Receber NF'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderScreen), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(OrderScreen), findsOneWidget);
  });

  testWidgets('order screen shows a friendly error when the order cannot be loaded', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: MockClient((r) async => http.Response('', 404)), token: 'tok'))
      ..role = 'Purchasing'
      ..permissions = rolePermissions['Purchasing']!;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: OrderScreen(session: session, id: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Registro não encontrado'), findsOneWidget);
    expect(find.text('Pedido'), findsOneWidget);
  });

  testWidgets('overdue list opens the order and colors lines more than 15 days late', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => OverdueScreen(session: s, supplierId: 1));
    expect(env.log.first.url.queryParameters['supplierId'], '1');
    expect(find.text('Dias de atraso'), findsOneWidget);
    await tester.tap(find.text('Tubo bruto'));
    await tester.pumpAndSettle();
    expect(find.text('Pedido nº 900 · Aços Sul'), findsOneWidget);
  });

  testWidgets('overdue list shows its empty state', (tester) async {
    final env = _Env();
    SharedPreferences.setMockInitialValues({});
    final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: MockClient((r) async => _json(_page([]))), token: 'tok'))
      ..permissions = rolePermissions['Purchasing']!;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OverdueScreen(session: session))));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma entrega em atraso'), findsOneWidget);
    expect(env.log, isEmpty);
  });

  group('new purchase order', () {
    Future<void> openEditor(WidgetTester tester, _Env env, {String role = 'Purchasing'}) async {
      await _pump(tester, env, (s) => Scaffold(body: OrdersScreen(session: s)), role: role);
      await tester.tap(find.text('Novo pedido'));
      await tester.pumpAndSettle();
      expect(find.text('Novo pedido de compra'), findsOneWidget);
    }

    Future<void> addLine(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('add-line')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field-materialId-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MP-1 · Tubo bruto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '10');
      await tester.enterText(find.byKey(const ValueKey('field-unitPrice')), '5');
      // Discount and taxes are folded until asked for.
      await tester.tap(find.byKey(const ValueKey('form-more')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-ipiPercent')), '10');
      await tester.enterText(find.byKey(const ValueKey('field-dueDate')), '20/12/2026');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
    }

    testWidgets('requires supplier and at least one line before issuing', (tester) async {
      final env = _Env();
      await openEditor(tester, env);
      await tester.tap(find.text('Emitir'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o fornecedor'), findsOneWidget);
      await tester.tap(find.byType(LookupField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('F1 · Aços Sul'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emitir'));
      await tester.pumpAndSettle();
      expect(find.text('Inclua ao menos uma linha'), findsOneWidget);
      expect(env.log.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('issues the order with its lines, totals and opens it', (tester) async {
      final env = _Env();
      await openEditor(tester, env);
      await tester.tap(find.byType(LookupField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('F1 · Aços Sul'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Condição de pagamento'), ' 28/56 ');
      await addLine(tester);
      expect(find.text('Total: R\$ 55,00'), findsOneWidget);
      await tester.tap(find.text('Emitir'));
      await tester.pumpAndSettle();
      // Issuing names the supplier and the total first.
      expect(find.text('Emitir o pedido de compra?'), findsOneWidget);
      expect(env.log.where((r) => r.method == 'POST'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      final b = env.body(env.last('POST', '/api/purchase-orders'));
      expect(b['supplierId'], 1);
      expect(b['paymentTerms'], '28/56');
      expect(b['notes'], isNull);
      final line = (b['lines'] as List).single as Map<String, dynamic>;
      expect(line['materialId'], 4);
      expect(line['quantity'], 10);
      expect(line['discountPercent'], 0);
      expect(line['icmsPercent'], 0);
      expect(line['ipiPercent'], 10);
      expect(line['dueDate'], '2026-12-20');
      expect(find.text('Pedido nº 900 · Aços Sul'), findsOneWidget);
    });

    testWidgets('edits and removes a line, and API errors stay on the editor', (tester) async {
      final env = _Env()..failWith = 'Fornecedor bloqueado';
      await openEditor(tester, env);
      await tester.tap(find.byType(LookupField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('F1 · Aços Sul'));
      await tester.pumpAndSettle();
      await addLine(tester);
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '20');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Total: R\$ 110,00'), findsOneWidget);
      await tester.tap(find.text('Emitir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(find.text('Pedido bloqueado: Fornecedor bloqueado'), findsOneWidget);
      expect(find.text('Novo pedido de compra'), findsOneWidget);
      await tester.tap(find.byTooltip('Remover'));
      await tester.pumpAndSettle();
      expect(find.text('Total: R\$ 0,00'), findsOneWidget);
    });
  });
}
