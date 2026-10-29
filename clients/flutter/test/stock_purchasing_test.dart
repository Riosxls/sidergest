import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/main.dart';
import 'package:ebt_engenharia/screens/orders.dart';
import 'package:ebt_engenharia/screens/quotations.dart';
import 'package:ebt_engenharia/screens/shell.dart';
import 'package:ebt_engenharia/screens/stock_closing.dart';
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
  String role = 'Stock';

  final material = {'id': 4, 'code': 'BOB-15', 'description': 'Bobina 1,5mm', 'stockUnit': 'KG', 'purchaseUnit': 'KG'};
  final location = {'id': 1, 'code': 'ALM', 'name': 'Almoxarifado', 'kind': 'Internal', 'active': true};
  final supplier = {'id': 1, 'name': 'Aços Sul', 'tradeName': null, 'legacyCode': '77', 'groupCode': null, 'active': true, 'addressCount': 1};

  late final doc = <String, dynamic>{
    'id': 50,
    'type': 'Issue',
    'date': '2026-10-26',
    'reference': 'OP-1',
    'supplierId': null,
    'customerId': null,
    'notes': null,
    'reversalOfId': null,
    'reversed': false,
    'createdBy': 'est',
    'createdAt': '2026-10-26T12:00:00Z',
    'movements': [
      {
        'id': 1,
        'documentId': 50,
        'type': 'Issue',
        'date': '2026-10-26',
        'materialId': 4,
        'productId': null,
        'itemCode': 'BOB-15',
        'locationId': 1,
        'locationCode': 'ALM',
        'lotId': 3,
        'lotCode': 'L-3',
        'quantity': -10,
        'unitCost': 5.5,
        'icmsRate': 0,
        'reservationId': null,
        'reference': 'OP-1',
        'balanceAfter': null,
      },
    ],
  };

  final lot = <String, dynamic>{
    'id': 3,
    'materialId': 4,
    'productId': null,
    'itemCode': 'BOB-15',
    'code': 'L-3',
    'status': 'Quarantine',
    'supplierId': 1,
    'invoiceNumber': '123',
    'heatNumber': 'H9',
    'receivedOn': '2026-10-20',
    'inspectionNote': null,
    'inspectedBy': null,
    'inspectedAt': null,
    'quantity': 500,
  };

  final requisition = <String, dynamic>{
    'id': 11,
    'number': 101,
    'materialId': 4,
    'materialCode': 'BOB-15',
    'description': 'Bobina 1,5mm',
    'unit': 'KG',
    'quantity': 1000,
    'approvedQuantity': null,
    'department': 'PCP',
    'neededBy': '2026-11-10',
    'application': null,
    'notes': null,
    'status': 'PendingApproval',
    'requestedBy': 'pcp',
    'requestedAt': '2026-10-25T10:00:00Z',
    'decidedBy': null,
    'decidedAt': null,
    'decisionNote': null,
    'quotationId': null,
    'quotationNumber': null,
    'purchaseOrderId': null,
    'purchaseOrderNumber': null,
  };

  String bidStatus = 'Pending';

  Map<String, dynamic> quotation() => {
    'id': 7,
    'number': 70,
    'status': 'Open',
    'notes': null,
    'createdBy': 'comp',
    'createdAt': '2026-10-20T10:00:00Z',
    'items': [
      {
        'id': 21,
        'item': 1,
        'materialId': 4,
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
            'unitPrice': 6.2,
            'discountPercent': 0,
            'icmsPercent': 12,
            'ipiPercent': 5,
            'leadTimeDays': 10,
            'paymentTerms': '28',
            'notes': null,
            'status': bidStatus,
            'respondedAt': '2026-10-21T10:00:00Z',
          },
          {
            'id': 32,
            'supplierId': 2,
            'supplierName': 'Usina Norte',
            'unitPrice': null,
            'discountPercent': 0,
            'icmsPercent': 0,
            'ipiPercent': 0,
            'leadTimeDays': null,
            'paymentTerms': null,
            'notes': null,
            'status': 'Pending',
            'respondedAt': null,
          },
        ],
      },
    ],
  };

  List<Map<String, dynamic>> comparison() => [
    {
      'itemId': 21,
      'item': 1,
      'description': 'Bobina 1,5mm',
      'unit': 'KG',
      'quantity': 1000,
      'lastUnitPrice': 6.0,
      'lastPurchaseDate': '2026-09-01',
      'lastSupplierName': 'Aços Sul',
      'bids': [
        {
          'bidId': 31,
          'supplierId': 1,
          'supplierName': 'Aços Sul',
          'unitPrice': 6.2,
          'netUnitPrice': 6.2,
          'landedUnitPrice': 6.51,
          'lineTotal': 6510,
          'leadTimeDays': 10,
          'paymentTerms': '28',
          'rank': 1,
          'status': bidStatus,
        },
      ],
      'pendingSupplierIds': [2],
    },
  ];

  final order = <String, dynamic>{
    'id': 90,
    'number': 900,
    'supplierId': 1,
    'supplierName': 'Aços Sul',
    'status': 'Open',
    'paymentTerms': '28',
    'notes': null,
    'issuedBy': 'comp',
    'issuedAt': '2026-10-01T10:00:00Z',
    'closedBy': null,
    'closedAt': null,
    'closeReason': null,
    'total': 6510,
    'lines': [
      {
        'id': 91,
        'lineNumber': 1,
        'materialId': 4,
        'materialCode': 'BOB-15',
        'description': 'Bobina 1,5mm',
        'unit': 'KG',
        'quantity': 1000,
        'unitPrice': 6.2,
        'discountPercent': 0,
        'icmsPercent': 12,
        'ipiPercent': 5,
        'dueDate': '2026-10-10',
        'receivedQuantity': 0,
        'openQuantity': 1000,
        'closed': false,
        'quotationBidId': 31,
        'total': 6510,
      },
    ],
  };

  final overdue = [
    {
      'purchaseOrderId': 90,
      'purchaseOrderNumber': 900,
      'lineId': 91,
      'lineNumber': 1,
      'supplierId': 1,
      'supplierName': 'Aços Sul',
      'description': 'Bobina 1,5mm',
      'unit': 'KG',
      'quantity': 1000,
      'receivedQuantity': 0,
      'openQuantity': 1000,
      'dueDate': '2026-10-10',
      'daysLate': 16,
    },
  ];

  Map<String, dynamic> get orderSummary => {
    'id': 90,
    'number': 900,
    'supplierId': 1,
    'supplierName': 'Aços Sul',
    'status': 'Open',
    'issuedAt': '2026-10-01T10:00:00Z',
    'nextDueDate': '2026-10-10',
    'lineCount': 1,
  };

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);

  MockClient get client => MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    final q = r.url.queryParameters;
    final m = r.method;
    if (r.headers['Authorization'] != 'Bearer tok') return http.Response('', 401);
    if (p == '/api/materials' || p == '/api/products') return json(page(p == '/api/materials' ? [material] : []));
    if (p == '/api/materials/4') return json(material);
    if (p == '/api/stock-locations') return json(page([location]));
    if (p == '/api/stock-locations/1') return json(location);
    if (p == '/api/suppliers') return json(page([supplier]));
    if (p == '/api/suppliers/1') return json(supplier);
    if (p == '/api/stock/documents' && m == 'POST') {
      final b = body(r);
      if ((b['lines'] as List).isEmpty) return json({'title': 'x'}, 400);
      return json(doc, 201);
    }
    if (p == '/api/stock/documents') return json(page([]));
    if (p == '/api/stock/documents/50') return json(doc);
    if (p == '/api/stock/documents/50/reverse') {
      doc['reversed'] = true;
      return json({...doc, 'id': 51, 'type': 'Reversal', 'reversalOfId': 50, 'reversed': false}, 201);
    }
    if (p == '/api/stock/lots') return json(page(q['status'] == null || q['status'] == lot['status'] ? [lot] : []));
    if (p == '/api/stock/lots/3/inspection') {
      lot['status'] = body(r)['status'];
      return json(lot);
    }
    if (p == '/api/stock/reservations') return json(page([]));
    if (p == '/api/stock/closings') {
      return json([
        {'period': 202609, 'closedBy': 'est', 'closedAt': '2026-10-02T10:00:00Z'},
      ]);
    }
    if (p == '/api/stock/average-costs/preview') {
      return json([
        {
          'period': int.parse(q['period']!),
          'thicknessMm': 1.5,
          'materialId': null,
          'openingQuantity': 1000,
          'openingAverage': 5.2,
          'purchaseQuantity': 500,
          'purchaseValue': 2800,
          'serviceQuantity': 0,
          'serviceValue': 0,
          'monthAverage': 5.6,
          'average': 5.3333,
          'averageGross': 6.1,
          'imported': false,
        },
      ]);
    }
    if (p.startsWith('/api/stock/closings/') && m == 'POST') return json({'period': 202610, 'closedBy': 'est', 'closedAt': '2026-11-01T10:00:00Z'}, 201);
    if (p == '/api/requisitions') return json(page(q['status'] == null || q['status'] == requisition['status'] ? [requisition] : []));
    if (p == '/api/requisitions/11/approve') {
      requisition['status'] = 'Approved';
      requisition['approvedQuantity'] = body(r)['approvedQuantity'];
      return json(requisition);
    }
    if (p == '/api/quotations') return json(page([]));
    if (p == '/api/quotations/7') return json(quotation());
    if (p == '/api/quotations/7/comparison') return json(comparison());
    if (p == '/api/quotations/7/items/21/award') {
      bidStatus = 'Approved';
      return json(quotation());
    }
    if (p == '/api/purchase-orders/from-quotation') return json(order, 201);
    if (p == '/api/purchase-orders') return json(page([orderSummary]));
    if (p == '/api/purchase-orders/90') return json(order);
    if (p == '/api/goods-receipts' && m == 'POST') return json({'id': 5, 'number': 55}, 201);
    if (p == '/api/goods-receipts') return json(page([]));
    if (p == '/api/goods-receipts/5') {
      return json({
        'id': 5,
        'number': 55,
        'supplierId': 1,
        'supplierName': 'Aços Sul',
        'invoiceNumber': '4455',
        'invoiceSeries': '1',
        'invoiceDate': '2026-10-26',
        'receivedAt': '2026-10-26T15:00:00Z',
        'receivedBy': 'comp',
        'invoiceTotal': 2600,
        'calculatedTotal': 2604,
        'divergent': true,
        'divergenceJustification': 'Frete',
        'notes': null,
        'lines': [],
        'installments': [
          {'sequence': 1, 'dueDate': '2026-11-23', 'amount': 2600},
        ],
      });
    }
    if (p == '/api/purchasing/overdue') return json(overdue);
    if (p == '/api/suppliers/1/performance') {
      return json({
        'supplierId': 1,
        'supplierName': 'Aços Sul',
        'orders': 3,
        'openOrders': 1,
        'orderedValue': 20000,
        'receipts': 2,
        'receivedValue': 12000,
        'receivedLines': 4,
        'onTimeLines': 3,
        'onTimePercent': 75.0,
        'averageDaysLate': 2.5,
        'overdueLines': 1,
      });
    }
    if (p == '/api/products') return json(page([]));
    return json(page([]));
  });
}

Future<Session> pumpScreen(WidgetTester tester, Fake fake, Widget Function(Session s) screen, {Size size = const Size(1400, 1800)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
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

Future<void> pick(WidgetTester tester, String key, String item) async {
  await tester.tap(find.byKey(ValueKey('field-$key-0')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  test('Brazilian dates, numbers and periods', () {
    expect(fmtDay('2026-10-05'), '05/10/2026');
    expect(parseDate('5/10/2026'), '2026-10-05');
    expect(parseDate('31/02/2026'), isNull);
    expect(fmtNum(1234567.891), '1.234.567,89');
    expect(fmtMoney(-12.5), 'R\$ -12,50');
    expect(fmtPeriod(202610), '10/2026');
    expect(parsePeriod('3/2026'), 202603);
    expect(nextPeriod(202612), 202701);
  });

  testWidgets('stock user posts an issue, opens the document and reverses it', (tester) async {
    final fake = Fake();
    await pumpScreen(
      tester,
      fake,
      (s) => Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => Shell(session: s)),
      ),
    );
    await openScreen(tester, 'Estoque', 'documents');
    await tester.tap(find.text('Novo lançamento'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('post-stock')));
    await tester.pumpAndSettle();
    expect(find.text('Inclua ao menos uma linha'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('post-reference')), 'OP-1');
    await tester.tap(find.byKey(const ValueKey('add-line')));
    await tester.pumpAndSettle();
    await pick(tester, 'materialId', 'BOB-15 · Bobina 1,5mm');
    await pick(tester, 'locationId', 'ALM · Almoxarifado');
    await tester.enterText(find.byKey(const ValueKey('field-quantity')), '10,5');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('BOB-15 · Bobina 1,5mm'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('post-stock')));
    await tester.pumpAndSettle();
    final b = fake.body(fake.last('POST', '/api/stock/documents'));
    expect(b['type'], 'Issue');
    expect(b['reference'], 'OP-1');
    expect(b['lines'], [
      {'materialId': 4, 'productId': null, 'locationId': 1, 'quantity': 10.5, 'lotId': null, 'reservationId': null},
    ]);

    expect(find.text('Nº 50 · Requisição (consumo)'), findsOneWidget);
    expect(find.text('L-3'), findsOneWidget);
    await tester.tap(find.text('Estornar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'Lançado errado');
    await tester.tap(find.widgetWithText(FilledButton, 'Estornar'));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/stock/documents/50/reverse'))['notes'], 'Lançado errado');
    expect(find.text('Estornar'), findsNothing);
  });

  testWidgets('quarantine lot is released by inspection', (tester) async {
    final fake = Fake();
    await pumpScreen(tester, fake, (s) => Shell(session: s));
    await openScreen(tester, 'Estoque', 'lots');
    expect(fake.last('GET', '/api/stock/lots').url.queryParameters['status'], 'Quarantine');
    await tester.tap(find.text('L-3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lot-release')));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('PUT', '/api/stock/lots/3/inspection'))['status'], 'Released');
    expect(find.text('L-3'), findsNothing);
  });

  testWidgets('monthly close shows the preview and closes the next period', (tester) async {
    final fake = Fake();
    await pumpScreen(tester, fake, (s) => ClosingScreen(session: s));
    expect(find.text('10/2026'), findsOneWidget);
    expect(fake.last('GET', '/api/stock/average-costs/preview').url.queryParameters['period'], '202610');
    expect(find.text('5,3333'), findsOneWidget);
    await tester.tap(find.text('Fechar mês'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(fake.last('POST', '/api/stock/closings/202610'), isNotNull);
    expect(find.text('Reabrir 09/2026'), findsNothing);
  });

  testWidgets('reader cannot post stock or approve requisitions', (tester) async {
    final fake = Fake()..role = 'Reader';
    await pumpScreen(tester, fake, (s) => Shell(session: s));
    await openScreen(tester, 'Estoque', 'documents');
    expect(find.text('Novo lançamento'), findsNothing);
    await openScreen(tester, 'Suprimentos', 'requisitions');
    await tester.tap(find.text('101'));
    await tester.pumpAndSettle();
    expect(find.text('Aprovar'), findsNothing);
    expect(find.text('Cancelar'), findsNothing);
  });

  testWidgets('buyer approves a requisition with a reduced quantity', (tester) async {
    final fake = Fake()..role = 'Purchasing';
    await pumpScreen(tester, fake, (s) => Shell(session: s));
    await openScreen(tester, 'Suprimentos', 'requisitions');
    expect(fake.last('GET', '/api/requisitions').url.queryParameters['status'], 'PendingApproval');
    await tester.tap(find.text('101'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('req-approve')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-approvedQuantity')), '800');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/requisitions/11/approve'))['approvedQuantity'], 800);
    expect(find.text('101'), findsNothing);
  });

  testWidgets('comparison ranks bids, award and order generation', (tester) async {
    final fake = Fake()..role = 'Purchasing';
    await pumpScreen(tester, fake, (s) => QuotationScreen(session: s, id: 7));
    expect(find.text('Sem resposta'), findsOneWidget);
    await tester.tap(find.text('Comparativo'));
    await tester.pumpAndSettle();
    expect(find.text('1º'), findsOneWidget);
    expect(find.text('+8,5 %'), findsOneWidget);
    expect(find.textContaining('Usina Norte'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('award-31')));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/quotations/7/items/21/award'))['bidId'], 31);
    expect(find.byKey(const ValueKey('award-31')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('quote-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Aços Sul'));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/purchase-orders/from-quotation')), {'quotationId': 7, 'supplierId': 1});
    expect(find.text('Pedido nº 900 · Aços Sul'), findsOneWidget);
  });

  testWidgets('receiving an invoice with divergence requires justification', (tester) async {
    final fake = Fake()..role = 'Stock';
    await pumpScreen(tester, fake, (s) => OrderScreen(session: s, id: 90));
    await tester.tap(find.text('Receber NF'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pedido 900/1'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('receive-invoice')), '4455');
    await tester.enterText(find.byKey(const ValueKey('receive-qty-91')), '400');
    await tester.enterText(find.byKey(const ValueKey('receive-total')), '2600');
    await tester.pumpAndSettle();
    expect(find.textContaining('Total calculado: R\$ 2.604,00'), findsOneWidget);
    expect(find.text('Justificativa da divergência *'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Justificativa da divergência *'), 'Frete');
    await tester.tap(find.byKey(const ValueKey('receive-save')));
    await tester.pumpAndSettle();
    final b = fake.body(fake.last('POST', '/api/goods-receipts'));
    expect(b['supplierId'], 1);
    expect(b['invoiceTotal'], 2600);
    expect(b['divergenceJustification'], 'Frete');
    expect(b['lines'], [
      {'purchaseOrderLineId': 91, 'quantity': 400, 'unitPrice': 6.2, 'lotCode': null},
    ]);
    expect(find.text('Recebimento nº 5'), findsOneWidget);
    expect(find.text('23/11/2026'), findsOneWidget);
  });

  testWidgets('purchasing dashboard on a phone shows overdue lines and on-time rate', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = Fake()..role = 'Purchasing';
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session =
        Session(
            api: ApiClient(baseUrl: 'http://api.test', client: fake.client, token: 'tok'),
          )
          ..username = 'comp'
          ..role = 'Purchasing'
          ..permissions = rolePermissions['Purchasing']!;
    await tester.pumpWidget(EbtApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('Suprimentos'), findsWidgets);
    expect(find.text('Entregas em atraso'), findsOneWidget);
    await tester.tap(find.text('Entregas em atraso'));
    await tester.pumpAndSettle();
    expect(find.textContaining('16 d · ped. 900'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    await openModule(tester, 'Suprimentos');
    await tester.scrollUntilVisible(find.text('75,0'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('75,0'), findsOneWidget);
  });
}
