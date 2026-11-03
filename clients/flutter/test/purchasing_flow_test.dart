import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/orders.dart';
import 'package:ebt_engenharia/screens/quotations.dart';
import 'package:ebt_engenharia/screens/receipts.dart';
import 'package:ebt_engenharia/screens/record_links.dart';
import 'package:ebt_engenharia/screens/requisitions.dart';
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

class _Env {
  String requisitionStatus = 'Quoting';
  final log = <http.Request>[];

  Map<String, dynamic> requisition() => {
    'id': 11,
    'number': 101,
    'materialCode': 'BOB-15',
    'description': 'Bobina 1,5mm',
    'unit': 'KG',
    'quantity': 1000,
    'approvedQuantity': 1000,
    'status': requisitionStatus,
    'requestedBy': 'ana',
    'requestedAt': '2026-10-20T12:00:00Z',
    'quotationId': requisitionStatus == 'Quoting' ? 7 : null,
    'quotationNumber': requisitionStatus == 'Quoting' ? 7 : null,
    'purchaseOrderId': null,
    'purchaseOrderNumber': null,
  };

  Map<String, dynamic> quotation() => {
    'id': 7,
    'number': 7,
    'status': 'Open',
    'createdAt': '2026-10-21T12:00:00Z',
    'requisitions': [
      {'id': 11, 'number': 101},
    ],
    'orders': [
      {'id': 90, 'number': 900},
    ],
    'orderedSupplierIds': [],
    'items': [
      {
        'id': 21,
        'item': 1,
        'materialCode': 'BOB-15',
        'description': 'Bobina 1,5mm',
        'unit': 'KG',
        'quantity': 1000,
        'requisitionNumbers': [101],
        'bids': [
          {
            'id': 31,
            'supplierId': 1,
            'supplierName': 'Aços Sul',
            'unitPrice': null,
            'discountPercent': 0,
            'icmsPercent': 0,
            'ipiPercent': 0,
            'leadTimeDays': null,
            'paymentTerms': null,
            'status': 'Pending',
          },
        ],
      },
    ],
  };

  Map<String, dynamic> order() => {
    'id': 90,
    'number': 900,
    'supplierId': 1,
    'supplierName': 'Aços Sul',
    'status': 'Open',
    'issuedBy': 'comp',
    'issuedAt': '2026-10-22T12:00:00Z',
    'total': 620,
    'quotationId': 7,
    'quotationNumber': 7,
    'requisitions': [
      {'id': 11, 'number': 101},
    ],
    'receipts': [
      {'id': 5, 'number': 55},
    ],
    'lines': [
      {
        'id': 91,
        'lineNumber': 1,
        'materialCode': 'BOB-15',
        'description': 'Bobina 1,5mm',
        'unit': 'KG',
        'quantity': 100,
        'unitPrice': 5,
        'discountPercent': 0,
        'icmsPercent': 0,
        'ipiPercent': 5,
        'dueDate': '2026-12-10',
        'receivedQuantity': 0,
        'openQuantity': 100,
        'closed': false,
        'total': 525,
      },
    ],
  };

  Map<String, dynamic> receipt() => {
    'id': 5,
    'number': 55,
    'supplierId': 1,
    'supplierName': 'Aços Sul',
    'invoiceNumber': '4455',
    'invoiceSeries': null,
    'invoiceDate': '2026-10-26',
    'receivedAt': '2026-10-26T15:00:00Z',
    'receivedBy': 'comp',
    'invoiceTotal': null,
    'calculatedTotal': 525,
    'divergent': false,
    'lines': [
      {
        'id': 1,
        'purchaseOrderId': 90,
        'purchaseOrderNumber': 900,
        'purchaseOrderLineId': 91,
        'materialCode': 'BOB-15',
        'description': 'Bobina 1,5mm',
        'quantity': 100,
        'unit': 'KG',
        'unitPrice': 5,
        'ipiPercent': 5,
        'total': 525,
      },
    ],
    'installments': [],
  };

  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  http.Response answer(http.Request r) {
    log.add(r);
    final p = r.url.path;
    if (r.method == 'POST' && p == '/api/goods-receipts') return _json({'id': 5, 'number': 55}, 201);
    if (p == '/api/requisitions/11') return _json(requisition());
    if (p == '/api/requisitions') return _json(_page([requisition()]));
    if (p == '/api/quotations/7') return _json(quotation());
    if (p == '/api/quotations/7/comparison') return _json([]);
    if (p == '/api/purchase-orders/90') return _json(order());
    if (p == '/api/purchase-orders') {
      return _json(_page([{'id': 90, 'number': 900, 'supplierId': 1, 'supplierName': 'Aços Sul', 'status': 'Open', 'issuedAt': '2026-10-22T12:00:00Z', 'lineCount': 1}]));
    }
    if (p == '/api/goods-receipts/5') return _json(receipt());
    if (p == '/api/suppliers') {
      return _json(_page([{'id': 1, 'code': 'F1', 'name': 'Aços Sul'}]));
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
  testWidgets('the requisition is a record kind and its page links to the quotation it is in', (tester) async {
    expect(recordLabels['requisition'], 'Requisição');
    final env = _Env();
    final session = await _pump(tester, env, (s) => Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => openRequisition(c, s, 11), child: const Text('abrir')))));
    expect(recordScreen(session, 'requisition', 11), isA<RequisitionScreen>());
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Requisição nº 101'), findsOneWidget);
    expect(find.text('Em cotação'), findsWidgets);
    // Only the stages with a record behind them are buttons, never the stage of the page itself.
    expect(find.byTooltip('Abrir: Cotação'), findsOneWidget);
    expect(find.byTooltip('Abrir: Requisição'), findsNothing);
    expect(find.byTooltip('Abrir: Pedido'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('path-tap-1')));
    await tester.pumpAndSettle();
    expect(find.text('Cotação nº 7 · Aberta'), findsOneWidget);
    // The quotation leads back to its requisition and forward to its order.
    expect(find.byTooltip('Abrir: Requisição'), findsOneWidget);
    expect(find.byTooltip('Abrir: Pedido'), findsOneWidget);
    expect(find.text('Req. 101'), findsOneWidget);
  });

  testWidgets('the purchase order path opens its quotation, requisition and receipt, and the receipt leads back', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => OrderScreen(session: s, id: 90));
    expect(find.byTooltip('Abrir: Cotação'), findsOneWidget);
    expect(find.byTooltip('Abrir: Recebimento'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('path-tap-3')));
    await tester.pumpAndSettle();
    expect(find.text('Recebimento nº 55'), findsOneWidget);
    // The receipt page has no null series crash and links to its order.
    expect(find.textContaining('NF 4455'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('path-tap-2')));
    await tester.pumpAndSettle();
    expect(find.text('Pedido nº 900 · Aços Sul'), findsOneWidget);
  });

  testWidgets('a new quotation starts with the requisition the user came from ticked, and asks before discarding', (tester) async {
    final env = _Env();
    await _pump(
      tester,
      env,
      (s) => Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => showDialog<void>(context: c, builder: (_) => NewQuotationDialog(api: s.api, initialRequisitionIds: const {11})),
            child: const Text('cotar'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('cotar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('(1 marcadas)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quote-add-supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('F1 · Aços Sul'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quote-create')), findsOneWidget);
  });

  group('receiving', () {
    testWidgets('a divergent total without a justification is refused and names the reason', (tester) async {
      final env = _Env();
      await _pump(tester, env, (s) => ReceiveScreen(session: s, supplierId: 1, supplierName: 'Aços Sul', purchaseOrderId: 90), role: 'Stock');
      await tester.enterText(find.byKey(const ValueKey('receive-invoice')), '4455');
      await tester.enterText(find.byKey(const ValueKey('receive-qty-91')), '100');
      await tester.enterText(find.byKey(const ValueKey('receive-total')), '500');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receive-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('informe a justificativa da divergência'), findsOneWidget);
      expect(env.log.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('a total that is not a number is refused', (tester) async {
      final env = _Env();
      await _pump(tester, env, (s) => ReceiveScreen(session: s, supplierId: 1, supplierName: 'Aços Sul'), role: 'Stock');
      await tester.enterText(find.byKey(const ValueKey('receive-invoice')), '4455');
      await tester.enterText(find.byKey(const ValueKey('receive-qty-91')), '100');
      await tester.enterText(find.byKey(const ValueKey('receive-total')), 'abc');
      await tester.tap(find.byKey(const ValueKey('receive-save')));
      await tester.pumpAndSettle();
      expect(find.text('Total da NF inválido'), findsOneWidget);
    });

    testWidgets('after registering, the receipt takes the form\'s place: Back does not return to the filled form', (tester) async {
      final env = _Env();
      await _pump(
        tester,
        env,
        (s) => Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => ReceiveScreen(session: s, supplierId: 1, supplierName: 'Aços Sul'))),
              child: const Text('receber'),
            ),
          ),
        ),
        role: 'Stock',
      );
      await tester.tap(find.text('receber'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('receive-invoice')), '4455');
      await tester.enterText(find.byKey(const ValueKey('receive-qty-91')), '100');
      await tester.tap(find.byKey(const ValueKey('receive-save')));
      await tester.pumpAndSettle();
      expect(env.body(env.last('POST', '/api/goods-receipts'))['invoiceNumber'], '4455');
      expect(find.text('Recebimento nº 55'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('receber'), findsOneWidget);
      expect(find.byKey(const ValueKey('receive-save')), findsNothing);
    });
  });
}
