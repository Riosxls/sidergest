import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/deliveries.dart';
import 'package:ebt_engenharia/screens/sales_common.dart';
import 'package:ebt_engenharia/screens/sales_orders.dart';
import 'package:ebt_engenharia/screens/sales_pipeline.dart';
import 'package:ebt_engenharia/screens/sales_quotes.dart';
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

class SalesFake {
  final log = <http.Request>[];
  String role = 'Sales';
  String quoteStatus = 'Draft';
  bool needsApproval = false;
  String orderStatus = 'Created';
  bool waived = false;
  bool startedOf = false;
  bool ready = false;
  String deliveryStatus = 'Planned';
  String? requestFileName;
  Map<String, dynamic>? credit;
  num listPrice = 100;
  String? rejectionNote;
  String? lostReason;
  String? supersededBy;
  int daysLeft = 11;

  List<Map<String, dynamic>> history(String action) => [
    if (rejectionNote != null) {'id': 3, 'action': 'approval-rejected', 'fromStatus': 'PendingApproval', 'toStatus': 'Draft', 'note': rejectionNote, 'user': 'gerente', 'at': '2026-10-27T12:00:00Z'},
    {'id': 2, 'action': action, 'fromStatus': 'Draft', 'toStatus': 'Sent', 'note': null, 'user': 'ana', 'at': '2026-10-26T12:00:00Z'},
    {'id': 1, 'action': 'created', 'fromStatus': null, 'toStatus': 'Draft', 'note': null, 'user': 'ana', 'at': '2026-10-25T12:00:00Z'},
  ];

  Map<String, dynamic> quote() => {
    'id': 5,
    'number': 31,
    'revision': 0,
    'reference': 'PROP 31',
    'customerId': 2,
    'customerName': 'BTS Tubos',
    'addressId': 3,
    'addressText': 'Av. Brasil, 100, Embu - SP',
    'contactName': 'Edilto',
    'contactEmail': 'compras@bts.com',
    'customerReference': 'RFQ-77',
    'paymentTermId': 1,
    'paymentTermName': '28 DDL',
    'freight': 'Cif',
    'validityDays': 15,
    'validUntil': quoteStatus == 'Sent' ? DateTime.now().add(Duration(days: daysLeft)).toIso8601String().substring(0, 10) : null,
    'conditions': 'Faturamento mínimo R\$ 300',
    'notes': null,
    'status': quoteStatus,
    'needsApproval': needsApproval,
    'approvedBy': null,
    'approvedAt': null,
    'sentAt': quoteStatus == 'Sent' ? '2026-10-26T12:00:00Z' : null,
    'sentTo': quoteStatus == 'Sent' ? 'compras@bts.com' : null,
    'decidedAt': null,
    'decisionBy': null,
    'decisionNote': null,
    'customerPo': null,
    'requestText': null,
    'requestFileName': requestFileName,
    'requestFileSize': requestFileName == null ? null : 2048,
    'salesOrderId': quoteStatus == 'Converted' ? 9 : null,
    'salesOrderReference': quoteStatus == 'Converted' ? 'PV 9' : null,
    'createdBy': 'ana',
    'createdAt': '2026-10-25T12:00:00Z',
    'lostReason': lostReason,
    'supersededById': supersededBy == null ? null : 8,
    'supersededBy': supersededBy,
    'totals': {'products': 10900, 'ipi': 500, 'total': 11400, 'maxDiscountPercent': needsApproval ? 10 : 0},
    'lines': [
      {
        'id': 1,
        'sequence': 10,
        'productId': 7,
        'productCode': 'TB-25',
        'customerPartNumber': 'BTS-001',
        'description': 'Tubo 25,4 x 1,5',
        'quantity': 100,
        'unit': 'PC',
        'unitPrice': 100,
        'listPrice': 100,
        'discountPercent': 0,
        'ipiPercent': 5,
        'icmsPercent': 18,
        'leadTimeDays': 20,
        'deliveryDate': null,
        'total': 10000,
      },
    ],
    'history': history('sent'),
  };

  Map<String, dynamic> order() => {
    'id': 9,
    'number': 9,
    'reference': 'PV 9',
    'customerId': 2,
    'customerName': 'BTS Tubos',
    'addressId': 3,
    'addressText': 'Av. Brasil, 100, Embu - SP',
    'customerPo': 'PO-4521',
    'paymentTermId': 1,
    'paymentTermName': '28 DDL',
    'freight': 'Cif',
    'status': orderStatus,
    'statusReason': null,
    'notes': null,
    'certificateWaived': waived,
    'quoteId': 5,
    'quoteReference': 'PROP 31',
    'createdBy': 'ana',
    'createdAt': '2026-10-26T12:00:00Z',
    'releasedBy': null,
    'releasedAt': null,
    'products': 10000,
    'ipi': 500,
    'total': 10500,
    'progress': ready ? 1 : 0.3,
    'ready': ready,
    'late': false,
    'credit': {'limit': 50000, 'open': 10500, 'thisOrder': 0, 'exceeded': false},
    'lines': [
      {
        'id': 40,
        'sequence': 10,
        'productId': 7,
        'productCode': 'TB-25',
        'customerPartNumber': 'BTS-001',
        'description': 'Tubo 25,4 x 1,5',
        'quantity': 100,
        'unit': 'PC',
        'unitPrice': 100,
        'ipiPercent': 5,
        'icmsPercent': 18,
        'dueDate': '2026-11-15',
        'total': 10000,
        'fromStock': orderStatus == 'Created' ? 0 : 30,
        'productionOrderId': orderStatus == 'Created' ? null : 12,
        'productionReference': orderStatus == 'Created' ? null : 'OF 500',
        'productionStatus': orderStatus == 'Created' ? null : 'Released',
        'produced': 0,
        'shipped': 0,
        'planned': 0,
        'remaining': 100,
        'available': 30,
        'ready': ready,
      },
    ],
    'deliveries': [],
    'history': history('created'),
  };

  Map<String, dynamic> delivery() => {
    'id': 15,
    'number': 15,
    'reference': 'ENT 15',
    'orderId': 9,
    'orderReference': 'PV 9',
    'customerId': 2,
    'customerName': 'BTS Tubos',
    'addressId': 3,
    'addressText': 'Av. Brasil, 100',
    'plannedDate': '2026-10-28',
    'status': deliveryStatus,
    'carrier': 'Próprio',
    'vehiclePlate': null,
    'invoiceNumber': null,
    'packages': 1,
    'grossWeightKg': 85.5,
    'stockDocumentId': null,
    'notes': null,
    'createdBy': 'ana',
    'createdAt': '2026-10-26T12:00:00Z',
    'shippedBy': null,
    'shippedAt': null,
    'deliveredAt': null,
    'receivedBy': null,
    'lines': [
      {
        'id': 1,
        'orderLineId': 40,
        'sequence': 10,
        'productId': 7,
        'productCode': 'TB-25',
        'description': 'Tubo 25,4 x 1,5',
        'quantity': 30,
        'unit': 'PC',
        'packages': 1,
      },
    ],
    'history': history('created'),
  };

  Map<String, dynamic> pipeline() => {
    'kpis': {
      'openQuotesValue': 11400,
      'openQuotes': 1,
      'winRate': 0.5,
      'openOrdersValue': 10500,
      'openOrders': 1,
      'lateOrders': 0,
      'readyToShip': 0,
      'pendingApprovals': 0,
    },
    'stages': [
      for (final k in ['quote', 'sent', 'accepted', 'po', 'order', 'production', 'ready', 'shipped', 'delivered'])
        {
          'key': k,
          'count': k == 'sent' || k == 'order' ? 1 : 0,
          'value': k == 'sent' ? 11400 : (k == 'order' ? 10500 : 0),
          'cards': [
            if (k == 'sent')
              {
                'kind': 'Quote',
                'id': 5,
                'reference': 'PROP 31',
                'customerId': 2,
                'customerName': 'BTS Tubos',
                'value': 11400,
                'status': 'Sent',
                'date': '2026-11-10',
                'progress': null,
                'badges': ['expiring'],
              },
            if (k == 'order')
              {
                'kind': 'Order',
                'id': 9,
                'reference': 'PV 9',
                'customerId': 2,
                'customerName': 'BTS Tubos',
                'value': 10500,
                'status': 'Created',
                'date': '2026-11-15',
                'progress': 0,
                'badges': <String>[],
              },
          ],
        },
    ],
  };

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);

  MockClient get client => MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    final m = r.method;
    if (p == '/api/sales/pipeline') return json(pipeline());
    if (p == '/api/sales/settings') {
      return json({'maxDiscountPercent': 5, 'defaultValidityDays': 15, 'minimumOrderValue': 0, 'shippingLocationId': null, 'defaultConditions': null});
    }
    if (p == '/api/sales/quotes/5' && m == 'GET') return json(quote());
    if (p == '/api/sales/quotes/5/credit') return json(credit ?? {'limit': null, 'open': 0, 'thisOrder': 11400, 'exceeded': false});
    if (p == '/api/sales/price') return json({'productId': 7, 'unitPrice': listPrice});
    if (p == '/api/sales/quotes/5/decline') {
      quoteStatus = 'Rejected';
      return json(quote());
    }
    if (p == '/api/sales/quotes/5/reopen') {
      quoteStatus = 'Draft';
      return json(quote());
    }
    if (p == '/api/sales/quotes/5/extend') {
      quoteStatus = 'Sent';
      return json(quote());
    }
    if (p == '/api/sales/quotes/5/duplicate') return json({...quote(), 'id': 6, 'reference': 'PROP 32', 'status': 'Draft'}, 201);
    if (p == '/api/sales/quotes/6' && m == 'GET') return json({...quote(), 'id': 6, 'reference': 'PROP 32', 'status': 'Draft'});
    if (p == '/api/sales/quotes/5/send') {
      quoteStatus = needsApproval && quoteStatus == 'Draft' ? 'PendingApproval' : 'Sent';
      return json(quote());
    }
    if (p == '/api/sales/quotes/5/approve') {
      quoteStatus = 'Approved';
      return json(quote());
    }
    if (p == '/api/sales/quotes/5/purchase-order') {
      quoteStatus = 'PurchaseOrder';
      return json(quote());
    }
    if (p == '/api/sales/quotes/5/accept') {
      quoteStatus = 'Accepted';
      return json(quote());
    }
    if (p == '/api/sales/quotes/5/convert') {
      quoteStatus = 'Converted';
      return json(order(), 201);
    }
    if (p == '/api/sales/orders/9' && m == 'GET') return json(order());
    if (p == '/api/sales/orders/9/release') {
      orderStatus = 'Released';
      return json(order());
    }
    if (p == '/api/sales/orders/9/cancel-preview') {
      return json({
        'plannedDeliveries': ['ENT 15'],
        'shippedDeliveries': [],
        'productionOrders': [
          {'reference': 'OF 500', 'status': startedOf ? 'InProduction' : 'Created', 'started': startedOf},
        ],
        'reservations': 1,
      });
    }
    if (p == '/api/sales/orders/9/cancel' || p == '/api/sales/orders/9/close-balance' || p == '/api/sales/orders/9/reschedule') {
      return json(order());
    }
    if (p == '/api/sales/certificates/for-delivery/15') return json([{'id': 70}]);
    if (p == '/api/sales/orders/9/deliveries') return json(delivery(), 201);
    if (p == '/api/sales/deliveries/15' && m == 'GET') return json(delivery());
    if (p == '/api/sales/deliveries/15/ship') {
      deliveryStatus = 'Shipped';
      return json({...delivery(), 'invoiceNumber': body(r)['invoiceNumber'], 'shippedAt': '2026-10-28T10:00:00Z'});
    }
    if (p == '/api/sales/quotes' || p == '/api/sales/orders' || p == '/api/sales/deliveries') return json(page([]));
    return json(page([]));
  });
}

Future<Session> pumpScreen(WidgetTester tester, SalesFake fake, Widget Function(Session s) screen) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session =
      Session(
          api: ApiClient(baseUrl: 'http://api.test', client: fake.client, token: 'tok'),
        )
        ..username = 'ana'
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
  test('sales role permissions and statuses map onto the flow path', () {
    final s = Session(api: ApiClient(baseUrl: 'http://x'))..role = 'Sales'..permissions = rolePermissions['Sales']!;
    expect(s.canSell, isTrue);
    expect(s.canApproveSales, isFalse);
    expect(s.canShip, isTrue);
    expect(quotePath('Sent'), (1, null));
    expect(quotePath('Accepted'), (2, null));
    expect(quotePath('PurchaseOrder'), (3, null));
    expect(quotePath('Rejected'), (2, 'Perdida'));
    expect(quotePath('Cancelled'), (0, 'Cancelada'));
    expect(quotePath('Cancelled', superseded: true), (0, 'Substituída'));
    expect(orderPath('Released'), (5, null));
    expect(orderPath('Released', ready: true), (6, null));
    expect(orderPath('Released', ready: true, certified: true), (7, null));
    expect(orderPath('Delivered'), (8, null));
    expect(deliveryPath('Cancelled'), (7, 'Cancelada'));
  });

  testWidgets('pipeline shows the stages and advances a sent proposal to accepted', (tester) async {
    final fake = SalesFake()..quoteStatus = 'Sent';
    await pumpScreen(tester, fake, (s) => SalesPipelineScreen(session: s));
    expect(find.text('Orçamentos em aberto'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-po')), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-production')), findsOneWidget);
    expect(find.text('PROP 31'), findsOneWidget);
    expect(find.text('Vence em breve'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('advance-Quote-5')));
    await tester.pumpAndSettle();
    expect(find.text('Cliente aprovou PROP 31'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'PO-4521');
    await tester.tap(find.text('Registrar aprovação'));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/sales/quotes/5/accept'))['customerPo'], 'PO-4521');
  });

  testWidgets('purchase order is attached on its own step after approval', (tester) async {
    final fake = SalesFake()..quoteStatus = 'Accepted';
    await pumpScreen(tester, fake, (s) => QuoteScreen(session: s, id: 5));
    expect(find.byKey(const ValueKey('quote-po-attach')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quote-po')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anexe o arquivo ou o texto'), findsOneWidget);
    expect(fake.log.where((r) => r.url.path.endsWith('/purchase-order')), isEmpty);
  });

  testWidgets('registered purchase order unlocks the sales order', (tester) async {
    final withFile = SalesFake()
      ..quoteStatus = 'Accepted'
      ..requestFileName = 'pedido-4521.pdf';
    await pumpScreen(tester, withFile, (s) => QuoteScreen(session: s, id: 5));
    expect(find.textContaining('pedido-4521.pdf'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quote-po')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(withFile.last('POST', '/api/sales/quotes/5/purchase-order'), isNotNull);
    expect(find.byKey(const ValueKey('quote-convert')), findsOneWidget);
  });

  testWidgets('new quote form has no purchase order attachment', (tester) async {
    final fake = SalesFake();
    await pumpScreen(tester, fake, (s) => QuoteEditorScreen(session: s));
    expect(find.byKey(const ValueKey('quote-request-attach')), findsNothing);
    expect(find.text('Observação do cliente'), findsNothing);
  });

  testWidgets('dragging an order card onto production releases it', (tester) async {
    final fake = SalesFake();
    await pumpScreen(tester, fake, (s) => SalesPipelineScreen(session: s));
    final card = find.byKey(const ValueKey('card-Order-9'));
    final target = tester.getCenter(find.byKey(const ValueKey('stage-production')));
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Liberar PV 9 para produção?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-step')));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/sales/orders/9/release'))['useStock'], isTrue);
  });

  testWidgets('discounted draft goes to approval and a manager approves it', (tester) async {
    final fake = SalesFake()..needsApproval = true;
    await pumpScreen(tester, fake, (s) => QuoteScreen(session: s, id: 5));
    expect(find.text('Desconto acima do limite'), findsOneWidget);
    expect(find.byKey(const ValueKey('path-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quote-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-step')));
    await tester.pumpAndSettle();
    expect(fake.last('POST', '/api/sales/quotes/5/send'), isNotNull);
    expect(find.text('Aguardando aprovação do gerente'), findsOneWidget);
    expect(find.byKey(const ValueKey('quote-approve')), findsNothing);

    final manager = SalesFake()
      ..role = 'SalesManager'
      ..needsApproval = true
      ..quoteStatus = 'PendingApproval';
    await pumpScreen(tester, manager, (s) => QuoteScreen(session: s, id: 5));
    await tester.tap(find.byKey(const ValueKey('quote-approve')));
    await tester.pumpAndSettle();
    expect(manager.last('POST', '/api/sales/quotes/5/approve'), isNotNull);
    expect(find.text('Desconto aprovado'), findsWidgets);
  });

  testWidgets('proposal with purchase order becomes a sales order', (tester) async {
    final fake = SalesFake()..quoteStatus = 'PurchaseOrder';
    await pumpScreen(tester, fake, (s) => QuoteScreen(session: s, id: 5));
    await tester.tap(find.byKey(const ValueKey('quote-convert')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-step')));
    await tester.pumpAndSettle();
    expect(fake.last('POST', '/api/sales/quotes/5/convert'), isNotNull);
    expect(find.text('PV 9 · BTS Tubos'), findsOneWidget);
    expect(find.byKey(const ValueKey('order-release')), findsOneWidget);
  });

  testWidgets('order release without stock, then plan a delivery', (tester) async {
    final fake = SalesFake();
    await pumpScreen(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
    await tester.tap(find.byKey(const ValueKey('order-release')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('use-stock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-step')));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/sales/orders/9/release'))['useStock'], isFalse);
    expect(find.text('OF 500 · Liberada'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('order-deliver')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dl-qty-40')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('dl-qty-40')), '30');
    await tester.tap(find.byKey(const ValueKey('delivery-ok')));
    await tester.pumpAndSettle();
    final b = fake.body(fake.last('POST', '/api/sales/orders/9/deliveries'));
    expect(b['lines'], [
      {'orderLineId': 40, 'quantity': 30},
    ]);
    expect(find.text('ENT 15 · BTS Tubos'), findsOneWidget);
  });

  testWidgets('stock user ships a planned delivery with the invoice number', (tester) async {
    final fake = SalesFake()
      ..role = 'Stock'
      ..waived = true;
    await pumpScreen(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
    await tester.tap(find.byKey(const ValueKey('delivery-ship')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-invoiceNumber')), '2581');
    await tester.enterText(find.byKey(const ValueKey('field-lotNumber')), 'L-77');
    await tester.enterText(find.byKey(const ValueKey('field-invoicedValue')), '420,5');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/sales/deliveries/15/ship'))['invoiceNumber'], '2581');
    expect(fake.body(fake.last('POST', '/api/sales/deliveries/15/ship'))['lotNumber'], 'L-77');
    expect(fake.body(fake.last('POST', '/api/sales/deliveries/15/ship'))['invoicedValue'], 420.5);
    expect(fake.body(fake.last('POST', '/api/sales/deliveries/15/ship')).containsKey('withoutCertificate'), isFalse);
    expect(find.byKey(const ValueKey('delivery-confirm')), findsOneWidget);
  });

  testWidgets('delivery creates the missing certificates in one click', (tester) async {
    final fake = SalesFake();
    await pumpScreen(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
    expect(find.text('Gerar certificado do item'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delivery-all-certificates')));
    await tester.pumpAndSettle();
    expect(fake.last('POST', '/api/sales/certificates/for-delivery/15'), isNotNull);
    expect(find.textContaining('1 certificado(s) criado(s)'), findsOneWidget);
  });

  testWidgets('shipping without a certificate or waiver asks first and says so to the API', (tester) async {
    final fake = SalesFake()..role = 'Stock';
    await pumpScreen(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
    expect(find.textContaining('ainda não tem certificado'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delivery-ship')));
    await tester.pumpAndSettle();
    expect(find.text('Expedir sem certificado?'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(fake.log.where((r) => r.url.path.endsWith('/ship')), isEmpty);
    await tester.tap(find.byKey(const ValueKey('delivery-ship')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ship-without-certificate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(fake.body(fake.last('POST', '/api/sales/deliveries/15/ship'))['withoutCertificate'], isTrue);
  });

  group('order changes after release', () {
    Future<SalesFake> open(WidgetTester tester, String status, {bool started = false}) async {
      final fake = SalesFake()
        ..orderStatus = status
        ..startedOf = started;
      await pumpScreen(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      return fake;
    }

    Future<void> menu(WidgetTester tester, String item) async {
      await tester.tap(find.byKey(const ValueKey('order-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('closing the balance lists the cut and needs a reason', (tester) async {
      final fake = await open(tester, 'PartiallyShipped');
      await tester.tap(find.byKey(const ValueKey('order-close-balance')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Item 10 · TB-25: 100 → 0 PC'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('confirm-step'))).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Cliente cortou o restante');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('POST', '/api/sales/orders/9/close-balance'))['reason'], 'Cliente cortou o restante');
    });

    testWidgets('no close-balance button before anything shipped', (tester) async {
      await open(tester, 'Released');
      expect(find.byKey(const ValueKey('order-close-balance')), findsNothing);
    });

    testWidgets('cancel shows what it touches and can stop OFs already running', (tester) async {
      final fake = await open(tester, 'Released', started: true);
      await menu(tester, 'Cancelar pedido');
      expect(find.textContaining('Entregas programadas, canceladas junto: ENT 15'), findsOneWidget);
      expect(find.textContaining('OF 500 (Em produção)'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Duplicado');
      await tester.tap(find.byKey(const ValueKey('reason-option')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/sales/orders/9/cancel'));
      expect(b['reason'], 'Duplicado');
      expect(b['cancelProduction'], isTrue);
    });

    testWidgets('cancel without running OFs offers no production choice', (tester) async {
      await open(tester, 'Released');
      await menu(tester, 'Cancelar pedido');
      expect(find.byKey(const ValueKey('reason-option')), findsNothing);
      expect(find.textContaining('OFs ainda não iniciadas, canceladas junto: OF 500'), findsOneWidget);
    });

    testWidgets('reschedule sends the new customer PO and every item date', (tester) async {
      final fake = await open(tester, 'Released');
      await menu(tester, 'Alterar prazos ou pedido do cliente');
      await tester.enterText(find.byKey(const ValueKey('field-customerPo')), 'PO-9');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/sales/orders/9/reschedule'));
      expect(b['customerPo'], 'PO-9');
      expect((b['lines'] as List).single['lineId'], 40);
    });

    testWidgets('a created order has no reschedule entry', (tester) async {
      await open(tester, 'Created');
      await tester.tap(find.byKey(const ValueKey('order-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Alterar prazos ou pedido do cliente'), findsNothing);
    });
  });

  testWidgets('credit warning shows on an open quote when the limit is exceeded', (tester) async {
    final fake = SalesFake()..credit = {'limit': 5000, 'open': 4000, 'thisOrder': 11400, 'exceeded': true};
    await pumpScreen(tester, fake, (s) => QuoteScreen(session: s, id: 5));
    expect(find.byKey(const ValueKey('quote-credit-banner')), findsOneWidget);
    expect(find.textContaining('só sai com liberação do gerente'), findsOneWidget);
  });

  testWidgets('no credit warning while the limit holds', (tester) async {
    await pumpScreen(tester, SalesFake(), (s) => QuoteScreen(session: s, id: 5));
    expect(find.byKey(const ValueKey('quote-credit-banner')), findsNothing);
  });

  testWidgets('a draft returned by the manager shows why', (tester) async {
    final fake = SalesFake()..rejectionNote = 'Desconto alto demais para este volume';
    await pumpScreen(tester, fake, (s) => QuoteScreen(session: s, id: 5));
    expect(find.textContaining('O gerente recusou o desconto: Desconto alto demais para este volume'), findsOneWidget);
  });

  testWidgets('customer decline asks for the main reason before posting', (tester) async {
    final fake = SalesFake()..quoteStatus = 'Sent';
    await pumpScreen(tester, fake, (s) => QuoteScreen(session: s, id: 5));
    await tester.tap(find.byKey(const ValueKey('quote-decline')));
    await tester.pumpAndSettle();
    expect(find.text('Venda perdida: cliente recusou PROP 31'), findsOneWidget);
    expect(find.textContaining('Motivo principal'), findsOneWidget);
    expect(fake.log.where((r) => r.url.path == '/api/sales/quotes/5/decline'), isEmpty);
  });

  group('quote outcomes are named after what the customer did', () {
    Future<SalesFake> open(WidgetTester tester, String status, {void Function(SalesFake)? tweak}) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = SalesFake()..quoteStatus = status;
      tweak?.call(fake);
      await pumpScreen(tester, fake, (s) => QuoteScreen(session: s, id: 5));
      return fake;
    }

    testWidgets('sent: approved, wants changes, refused, more time; no top-bar Revisar and no Cancelar in the menu', (tester) async {
      await open(tester, 'Sent');
      for (final k in ['quote-accept', 'quote-change', 'quote-decline', 'quote-extend']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(find.text('Nova revisão'), findsOneWidget);
      expect(find.text('Cliente recusou (venda perdida)'), findsOneWidget);
      expect(find.byKey(const ValueKey('quote-revise-top')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('quote-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Duplicar'), findsOneWidget);
      expect(find.text('Pedir análise de viabilidade'), findsOneWidget);
      expect(find.textContaining('Cancelar'), findsNothing, reason: 'a sent quote ends as lost, revised or extended, never "cancelled"');
    });

    testWidgets('"Nova revisão" on the card opens the revision dialog and says what happens to this version', (tester) async {
      final fake = await open(tester, 'Sent');
      await tester.tap(find.byKey(const ValueKey('quote-change')));
      await tester.pumpAndSettle();
      expect(find.text('Nova revisão de PROP 31'), findsOneWidget);
      expect(find.textContaining('Motivo da revisão'), findsOneWidget);
      expect(find.textContaining('passa a Substituída'), findsOneWidget);
      expect(fake.log.where((r) => r.url.path.endsWith('/revise')), isEmpty);
    });

    for (final status in ['Accepted', 'PurchaseOrder']) {
      testWidgets('$status: the customer can still give up, and the reason defaults to that', (tester) async {
        final fake = await open(tester, status);
        expect(find.byKey(const ValueKey('quote-change')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('quote-gave-up')));
        await tester.pumpAndSettle();
        expect(find.text('Cliente desistiu de PROP 31'), findsOneWidget, reason: status);
        expect(find.text('Cliente desistiu do pedido'), findsWidgets);
        expect(fake.log.where((r) => r.url.path.endsWith('/decline')), isEmpty);
      });
    }

    testWidgets('a refusal does not offer "desistiu" as a reason; it is for after approval', (tester) async {
      await open(tester, 'Sent');
      await tester.tap(find.byKey(const ValueKey('quote-decline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pumpAndSettle();
      expect(find.text('Preço'), findsWidgets);
      expect(find.text('Cliente desistiu do pedido'), findsNothing);
    });

    for (final status in ['PendingApproval', 'Approved']) {
      testWidgets('$status: go back to draft instead of revising', (tester) async {
        final fake = await open(tester, status);
        expect(find.byKey(const ValueKey('quote-reopen')), findsOneWidget, reason: status);
        await tester.tap(find.byKey(const ValueKey('quote-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Nova revisão'), findsNothing, reason: 'not sent yet: nothing to revise');
        expect(find.text('Cancelar orçamento'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5)); // close the menu
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('quote-reopen')));
        await tester.pumpAndSettle();
        expect(find.text('Voltar para rascunho?'), findsOneWidget);
        await tester.tap(find.text('Voltar para rascunho'));
        await tester.pumpAndSettle();
        expect(fake.last('POST', '/api/sales/quotes/5/reopen'), isNotNull);
      });
    }

    testWidgets('expired: extend the validity first, revise second', (tester) async {
      final fake = await open(tester, 'Expired');
      expect(find.text('Prorrogar validade'), findsOneWidget);
      expect(find.byKey(const ValueKey('quote-revise')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quote-extend')));
      await tester.pumpAndSettle();
      expect(find.text('Prorrogar validade de PROP 31'), findsOneWidget);
      expect(find.textContaining('Nova validade'), findsOneWidget);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final body = fake.body(fake.last('POST', '/api/sales/quotes/5/extend'));
      expect(body['validUntil'], isNotNull);
    });

    testWidgets('lost quote shows the reason in the card and in the badge', (tester) async {
      await open(tester, 'Rejected', tweak: (f) => f.lostReason = 'Price');
      expect(find.text('Venda perdida'), findsOneWidget);
      expect(find.text('Perdida · Preço'), findsOneWidget);
      expect(find.text('Retomar com nova revisão'), findsOneWidget);
    });

    testWidgets('a replaced version is "Substituída", not "Cancelada", and links to the live revision', (tester) async {
      await open(tester, 'Cancelled', tweak: (f) => f.supersededBy = 'PROP 31-B');
      expect(find.text('Substituída pela revisão PROP 31-B'), findsWidgets);
      expect(find.text('Cancelada'), findsNothing);
      expect(find.byKey(const ValueKey('quote-open-latest')), findsOneWidget);
    });

    testWidgets('the revision reason covers our own corrections too', (tester) async {
      await open(tester, 'Sent');
      await tester.tap(find.byKey(const ValueKey('quote-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pumpAndSettle();
      expect(find.text('Correção nossa (erro ou ajuste interno)'), findsOneWidget);
      expect(find.text('Cliente pediu: preço'), findsWidgets);
    });

    testWidgets('sent card: outcomes on the left, quiet actions on the right, the e-mail shown once', (tester) async {
      await open(tester, 'Sent');
      final accept = tester.getTopLeft(find.byKey(const ValueKey('quote-accept')));
      final extend = tester.getTopLeft(find.byKey(const ValueKey('quote-extend')));
      final mail = tester.getTopLeft(find.byKey(const ValueKey('quote-mail')));
      expect(extend.dx, greaterThan(accept.dx + 600), reason: 'Prorrogar validade sits at the right edge, away from the outcomes');
      expect(mail.dx, lessThan(extend.dx));
      expect(find.textContaining('compras@bts.com'), findsOneWidget, reason: 'only in the header contact');
      expect(find.textContaining('Enviada em'), findsOneWidget);
      expect(find.textContaining('Registre o que o cliente respondeu'), findsNothing);
    });

    testWidgets('the status is not repeated in a badge when the stage path already says it', (tester) async {
      await open(tester, 'Sent');
      expect(find.text('Enviada ao cliente'), findsOneWidget);
    });

    testWidgets('a draft keeps its badge, the path cannot tell draft from approval', (tester) async {
      await open(tester, 'Draft');
      expect(find.text('Rascunho'), findsOneWidget);
    });

    for (final (days, text) in [(11, '11 dias restantes'), (3, '3 dias restantes'), (1, 'Vence amanhã'), (0, 'Vence hoje'), (-2, 'Vencida há 2 dias')]) {
      testWidgets('validity chip at  days left says ""', (tester) async {
        await open(tester, 'Sent', tweak: (f) => f.daysLeft = days);
        expect(find.text(text), findsOneWidget);
      });
    }

    testWidgets('refusing and giving up are drawn as the negative outcomes, revising is neutral', (tester) async {
      await open(tester, 'Sent');
      final error = Theme.of(tester.element(find.byKey(const ValueKey('quote-decline')))).colorScheme.error;
      Color? fg(String key) => tester.widget<OutlinedButton>(find.byKey(ValueKey(key))).style?.foregroundColor?.resolve({});
      expect(fg('quote-decline'), error);
      expect(fg('quote-change'), isNot(error));
      expect(find.byTooltip('Altera itens ou preço. Esta versão fica como Substituída (só consulta) e uma nova revisão abre em rascunho.'), findsOneWidget);
    });

    testWidgets('a line without discount shows a dash, not an empty cell', (tester) async {
      await open(tester, 'Sent');
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('a draft can still be cancelled from the menu', (tester) async {
      await open(tester, 'Draft');
      await tester.tap(find.byKey(const ValueKey('quote-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Cancelar orçamento'), findsOneWidget);
      expect(find.text('Editar itens e condições'), findsOneWidget);
    });
  });

  testWidgets('duplicate from the menu posts the copy and opens it', (tester) async {
    final fake = SalesFake();
    await pumpScreen(tester, fake, (s) => QuoteScreen(session: s, id: 5));
    await tester.tap(find.byKey(const ValueKey('quote-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicar'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicar PROP 31'), findsOneWidget);
  });

  testWidgets('editor warns about a discount above the limit before the quote is sent', (tester) async {
    final fake = SalesFake();
    final quote = fake.quote();
    (quote['lines'] as List).first['unitPrice'] = 90; // 10% under the 100 list price, limit is 5%
    await pumpScreen(tester, fake, (s) => QuoteEditorScreen(session: s, quote: quote));
    expect(find.byKey(const ValueKey('quote-approval-banner')), findsOneWidget);
    expect(find.textContaining('limite 5%'), findsOneWidget);
    expect(find.text('Adicionar item'), findsOneWidget);
    expect(find.textContaining('ICMS'), findsWidgets);
  });

  testWidgets('editor shows no warning when the price matches the list', (tester) async {
    final fake = SalesFake();
    await pumpScreen(tester, fake, (s) => QuoteEditorScreen(session: s, quote: fake.quote()));
    expect(find.byKey(const ValueKey('quote-approval-banner')), findsNothing);
  });

  testWidgets('reader sees the pipeline without actions', (tester) async {
    final fake = SalesFake()..role = 'Reader';
    await pumpScreen(tester, fake, (s) => Shell(session: s));
    await openScreen(tester, 'Comercial', 'sales-pipeline');
    expect(find.byKey(const ValueKey('pipeline-new')), findsNothing);
    await tester.tap(find.text('PROP 31'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quote-send')), findsNothing);
  });
}
