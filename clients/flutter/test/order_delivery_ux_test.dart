// Order, delivery and Painel behaviour of the sales UI review: certificate coverage per item, NF pendente, lists that do not hide results,
// delivery quantities, credit banner and the Painel routing.
import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/certificates.dart';
import 'package:ebt_engenharia/screens/dashboard_data.dart';
import 'package:ebt_engenharia/screens/deliveries.dart';
import 'package:ebt_engenharia/screens/sales_common.dart';
import 'package:ebt_engenharia/screens/sales_orders.dart';
import 'package:ebt_engenharia/widgets/print_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'sales_more_support.dart';

Map<String, dynamic> _delivery({String status = 'Planned', List<Map<String, dynamic>> history = const [], String? invoiceNumber, Object? needsInvoice, bool twoLines = true}) => {
  'id': 15,
  'number': 15,
  'reference': 'ENT 15',
  'orderId': 9,
  'orderReference': 'PV 9',
  'customerId': 2,
  'customerName': 'BTS Tubos',
  'addressText': 'Av. Brasil, 100',
  'plannedDate': '2026-10-28',
  'status': status,
  'invoiceNumber': invoiceNumber,
  'packages': 1,
  'grossWeightKg': 85.5,
  'valueExIpi': 10000,
  'createdBy': 'ana',
  'createdAt': '2026-10-26T12:00:00Z',
  'lines': [
    {'id': 1, 'orderLineId': 40, 'productId': 7, 'sequence': 10, 'productCode': 'TB-25', 'description': 'Tubo', 'quantity': 40, 'unit': 'PC', 'packages': 1},
    if (twoLines) {'id': 2, 'orderLineId': 41, 'productId': 8, 'sequence': 20, 'productCode': 'TB-30', 'description': 'Tubo 30', 'quantity': 10, 'unit': 'PC', 'packages': 1},
  ],
  'history': history,
  'needsInvoice': ?needsInvoice,
};

const _pendingHistory = [
  {'id': 9, 'action': 'shipped', 'fromStatus': 'Planned', 'toStatus': 'Shipped', 'note': 'NF pendente', 'user': 'joao', 'at': '2026-10-27T12:00:00Z'},
];

/// An order of two items, ready to ship; item 10 has an issued certificate (read from its detail), item 20 has none.
MoreFake _twoItems() {
  final f = MoreFake();
  f.order['status'] = 'Released';
  f.order['ready'] = true;
  final lines = f.order['lines'] as List;
  lines.add({...(lines.first as Map<String, dynamic>), 'id': 41, 'sequence': 20, 'productId': 8, 'productCode': 'TB-30'});
  f.certs = [
    {'id': 70, 'reference': 'CERT 1', 'status': 'Issued', 'description': 'Tubo', 'quantity': 40, 'unit': 'PC', 'issueDate': '2026-10-28', 'deliveryId': null},
  ];
  f.overrides['GET /api/sales/certificates/70'] = (_) => jsonResp({...f.certs.first, 'orderLineId': 40, 'productId': 7});
  f.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery());
  return f;
}

Map<String, dynamic> _cert({String status = 'Issued', int? line, int? product, int? delivery}) => {'status': status, 'orderLineId': line, 'productId': product, 'deliveryId': delivery};

void main() {
  group('certificate coverage per item', () {
    final delivery = {
      'id': 15,
      'lines': [
        {'orderLineId': 40, 'productId': 7, 'sequence': 10},
        {'orderLineId': 41, 'productId': 8, 'sequence': 20},
      ],
    };
    List<Object?> missing(List<Map<String, dynamic>> certs) => uncoveredDeliveryLines(delivery, certs).map((l) => l['sequence']).toList();

    test('one certificate does not cover the other item', () => expect(missing([_cert(line: 40, product: 7)]), [20]));
    test('a certificate naming no line covers the items of its product', () => expect(missing([_cert(product: 8)]), [10]));
    test('both items covered', () => expect(missing([_cert(line: 40, product: 7), _cert(product: 8)]), isEmpty));
    test('a certificate of another delivery does not count, this one does', () {
      expect(missing([_cert(line: 40, product: 7, delivery: 99), _cert(line: 41, product: 8, delivery: 99)]), [10, 20]);
      expect(missing([_cert(line: 40, product: 7, delivery: 15), _cert(line: 41, product: 8, delivery: 15)]), isEmpty);
    });
    test('drafts and cancelled certificates do not cover', () {
      expect(missing([_cert(status: 'Draft', line: 40, product: 7), _cert(status: 'Cancelled', line: 41, product: 8)]), [10, 20]);
    });

    test('the order is certified when waived or when every item still to ship is covered by a certificate that can go with it', () {
      final order = {
        'certificateWaived': false,
        'lines': [
          {'id': 40, 'productId': 7, 'remaining': 100},
          {'id': 41, 'productId': 8, 'remaining': 0},
        ],
        'deliveries': [
          {'id': 15, 'status': 'Shipped'},
        ],
      };
      expect(orderCertified(order, [_cert(line: 40, product: 7)]), isTrue); // item 41 has nothing left to ship
      expect(orderCertified(order, [_cert(line: 40, product: 7, delivery: 15)]), isFalse); // tied to a delivery that already left
      expect(orderCertified(order, []), isFalse);
      expect(orderCertified({...order, 'certificateWaived': true}, []), isTrue);
    });

    test('the snapshot of an order ready to ship says the certificate is missing when it is not settled', () {
      final o = {'reference': 'PV 9', 'status': 'Released', 'ready': true};
      expect(orderSnapshot(o, certified: false).message, contains('falta o certificado'));
      expect(orderSnapshot(o, certified: true).message, 'Pronto para expedir: programe a entrega.');
    });

    test('empty "Encontrado" rows are named; a typed dash is a value, as on the server', () {
      expect(emptyFoundRows(['C', 'Espessura', 'LR'], ['0,08', ' ', '-']), ['Espessura']);
    });

    test('an NF is owed when the server says so or the shipment event says "NF pendente"', () {
      expect(deliveryNeedsInvoice({'needsInvoice': true, 'status': 'Delivered'}), isTrue);
      expect(deliveryNeedsInvoice({'needsInvoice': false, 'status': 'Shipped', 'history': _pendingHistory}), isFalse);
      expect(deliveryNeedsInvoice({'status': 'Shipped', 'history': _pendingHistory}), isTrue);
      expect(deliveryNeedsInvoice({'status': 'Shipped', 'invoiceNumber': '12', 'history': _pendingHistory}), isFalse);
      expect(deliveryNeedsInvoice({'status': 'Planned', 'history': _pendingHistory}), isFalse);
    });
  });

  group('delivery page', () {
    testWidgets('shipping names the items without an issued certificate and sends withoutCertificate', (tester) async {
      final fake = _twoItems();
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      expect(find.byKey(const ValueKey('delivery-uncovered')), findsOneWidget);
      await tapKey(tester, 'delivery-ship');
      expect(find.text('Expedir sem certificado?'), findsOneWidget);
      expect(find.textContaining('item 20 · TB-30'), findsOneWidget);
      expect(find.textContaining('item 10 · TB-25'), findsNothing);
      await tapKey(tester, 'ship-without-certificate');
      await tapText(tester, 'Salvar');
      expect(fake.body(fake.last('POST', '/api/sales/deliveries/15/ship'))['withoutCertificate'], isTrue);
    });

    testWidgets('with every item covered shipping asks nothing', (tester) async {
      final fake = _twoItems();
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery(twoLines: false));
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      expect(find.byKey(const ValueKey('delivery-uncovered')), findsNothing);
      await tapKey(tester, 'delivery-ship');
      expect(find.text('Expedir sem certificado?'), findsNothing);
      expect(find.text('Expedir ENT 15'), findsOneWidget);
    });

    testWidgets('a draft does not cover an item: it is counted as missing and not offered again', (tester) async {
      final fake = _twoItems();
      fake.order['certificateWaived'] = false;
      fake.certs = [
        {'id': 71, 'reference': 'CERT 2', 'status': 'Draft', 'description': 'Tubo', 'quantity': 40, 'unit': 'PC', 'issueDate': '2026-10-28', 'deliveryId': 15},
      ];
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      expect(find.textContaining('Sem certificado emitido: item 10, item 20'), findsOneWidget);
      // Two items missing, one draft already stands for one of them: one certificate left to generate.
      expect(find.text('Gerar certificado do item'), findsOneWidget);
    });

    testWidgets('the certificate picker lists the delivery items only and flags the covered one', (tester) async {
      final fake = _twoItems();
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      await tapKey(tester, 'delivery-new-certificate');
      expect(find.text('Certificado de qual item?'), findsOneWidget);
      expect(find.textContaining('(já tem certificado)'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('cert-pick-40')), matching: find.textContaining('já tem certificado')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('cert-pick-41')), matching: find.textContaining('TB-30')), findsOneWidget);
    });

    testWidgets('a delivery with one item skips the picker, even when the order has more', (tester) async {
      final fake = _twoItems();
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery(twoLines: false));
      fake.overrides['POST /api/sales/certificates'] = (_) => jsonResp({
        'id': 77,
        'reference': '2146-26',
        'company': 'EBT',
        'orderId': 9,
        'orderReference': 'PV 9',
        'issueDate': '2026-10-30',
        'quantity': 40,
        'unit': 'PC',
        'description': 'Tubo',
        'status': 'Draft',
        'measures': <Map<String, dynamic>>[],
      }, 201);
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      await tapKey(tester, 'delivery-new-certificate');
      expect(find.text('Certificado de qual item?'), findsNothing);
      expect(fake.body(fake.last('POST', '/api/sales/certificates'))['orderLineId'], 40);
    });

    testWidgets('a failed order read says so instead of failing silently', (tester) async {
      final fake = _twoItems();
      fake.overrides['GET /api/sales/orders/9'] = (_) => http.Response('{"detail":"fora do ar"}', 500, headers: {'content-type': 'application/json'});
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      await tapKey(tester, 'delivery-new-certificate');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Certificado de qual item?'), findsNothing);
    });

    testWidgets('a delivered delivery with the NF still owed shows the badge and "Emitir NF"', (tester) async {
      final fake = MoreFake();
      var emitted = false;
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery(status: 'Delivered', history: _pendingHistory, invoiceNumber: emitted ? '2582' : null));
      fake.overrides['POST /api/sales/deliveries/15/emit-invoice'] = (_) {
        emitted = true;
        return jsonResp(_delivery(status: 'Delivered', invoiceNumber: '2582'));
      };
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      expect(find.text('NF pendente'), findsWidgets);
      expect(find.textContaining('A NF ainda não foi emitida'), findsOneWidget);
      await tapKey(tester, 'delivery-emit-invoice');
      expect(fake.called('POST', '/api/sales/deliveries/15/emit-invoice'), isTrue);
      expect(find.byKey(const ValueKey('delivery-emit-invoice')), findsNothing);
      expect(find.textContaining('A NF ainda não foi emitida'), findsNothing); // the history still carries the old "NF pendente" note
    });

    testWidgets('the server flag alone is enough, and a user who cannot emit sees the badge but no button', (tester) async {
      final fake = MoreFake();
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery(status: 'Shipped', needsInvoice: true));
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15), role: 'Stock');
      expect(find.text('NF pendente'), findsWidgets);
      expect(find.byKey(const ValueKey('delivery-emit-invoice')), findsNothing);
    });

    testWidgets('who may not emit the NF gets no NF number field and is told Sales will issue it', (tester) async {
      final fake = MoreFake();
      fake.order['certificateWaived'] = true;
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery());
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15), role: 'Stock');
      await tapKey(tester, 'delivery-ship');
      expect(find.byKey(const ValueKey('field-invoiceNumber')), findsNothing);
      expect(find.textContaining('NF pendente'), findsWidgets);
      await tapText(tester, 'Salvar');
      expect(fake.body(fake.last('POST', '/api/sales/deliveries/15/ship')).containsKey('invoiceNumber'), isFalse);
    });

    testWidgets('Sales keeps the NF number field', (tester) async {
      final fake = MoreFake();
      fake.order['certificateWaived'] = true;
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery());
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      await tapKey(tester, 'delivery-ship');
      expect(find.byKey(const ValueKey('field-invoiceNumber')), findsOneWidget);
    });
  });

  group('deliveries list', () {
    List<Map<String, dynamic>> rows() => [
      {'id': 15, 'reference': 'ENT 15', 'orderReference': 'PV 9', 'customerName': 'BTS Tubos', 'plannedDate': '2026-10-28', 'status': 'Shipped', 'packages': 1, 'invoiceNumber': null, 'needsInvoice': true},
      {'id': 16, 'reference': 'ENT 16', 'orderReference': 'PV 9', 'customerName': 'BTS Tubos', 'plannedDate': '2026-10-29', 'status': 'Shipped', 'packages': 1, 'invoiceNumber': '2581', 'needsInvoice': false},
    ];

    testWidgets('the Planned default is dropped while searching, and the pending-NF chip filters', (tester) async {
      final fake = MoreFake();
      fake.overrides['GET /api/sales/deliveries'] = (_) => jsonResp(pageOf(rows()));
      await pumpMore(tester, fake, (s) => DeliveriesScreen(session: s));
      expect(fake.last('GET', '/api/sales/deliveries').url.queryParameters['status'], 'Planned');
      await tester.enterText(find.byType(TextField).first, '2581');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final q = fake.last('GET', '/api/sales/deliveries').url.queryParameters;
      expect(q['q'], '2581');
      expect(q.containsKey('status'), isFalse);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/sales/deliveries').url.queryParameters['status'], 'Planned');

      await tapKey(tester, 'deliveries-pending-invoice');
      final p = fake.last('GET', '/api/sales/deliveries').url.queryParameters;
      expect(p['pendingInvoice'], 'true');
      expect(p.containsKey('status'), isFalse);
      expect(find.text('ENT 15'), findsOneWidget);
      expect(find.text('ENT 16'), findsNothing); // the server flag says no NF is owed on it
      expect(find.text('NF pendente'), findsWidgets);
    });

    testWidgets('the Painel hands over the pending-invoice filter', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => DeliveriesScreen(session: s, initialFilter: DeliveriesScreen.pendingInvoiceFilter));
      final q = fake.last('GET', '/api/sales/deliveries').url.queryParameters;
      expect(q['pendingInvoice'], 'true');
      expect(q.containsKey('status'), isFalse);
    });
  });

  group('orders list', () {
    Map<String, dynamic> row(int id, {bool ready = false, bool late = false, String status = 'Released'}) =>
        {'id': id, 'reference': 'PV $id', 'customerName': 'BTS', 'status': status, 'billTo': 'Ebt', 'total': 100, 'progress': 0.5, 'ready': ready, 'late': late};

    testWidgets('the Painel "Prontos para expedir" opens the ready orders only', (tester) async {
      final fake = MoreFake();
      fake.overrides['GET /api/sales/orders'] = (_) => jsonResp(pageOf([row(1, ready: true), row(2), row(3, ready: true, status: 'Created')]));
      await pumpMore(tester, fake, (s) => SalesOrdersScreen(session: s, initialFilter: SalesOrdersScreen.readyFilter));
      expect(find.text('PV 1'), findsOneWidget);
      expect(find.text('PV 2'), findsNothing);
      expect(find.text('PV 3'), findsNothing);
    });

    testWidgets('"Pedidos atrasados" opens with the late filter sent to the server', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrdersScreen(session: s, initialFilter: SalesOrdersScreen.lateFilter));
      expect(fake.last('GET', '/api/sales/orders').url.queryParameters['late'], 'true');
    });

    testWidgets('"Somente abertos" is a default: dropped while searching, back when the search is cleared', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrdersScreen(session: s));
      expect(fake.last('GET', '/api/sales/orders').url.queryParameters['open'], 'true');
      await tester.enterText(find.byType(TextField).first, 'PV');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/sales/orders').url.queryParameters.containsKey('open'), isFalse);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/sales/orders').url.queryParameters['open'], 'true');
    });
  });

  group('order page', () {
    testWidgets('ready to ship waits for a certificate of every item, not just any one', (tester) async {
      final fake = _twoItems();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Produção pronta · falta o certificado'), findsOneWidget);
    });

    testWidgets('every item covered: ready to ship', (tester) async {
      final fake = _twoItems();
      fake.certs = [
        {'id': 70, 'reference': 'CERT 1', 'status': 'Issued', 'description': 'Tubo', 'quantity': 40, 'unit': 'PC', 'issueDate': '2026-10-28', 'deliveryId': null},
        {'id': 71, 'reference': 'CERT 2', 'status': 'Issued', 'description': 'Tubo 30', 'quantity': 10, 'unit': 'PC', 'issueDate': '2026-10-28', 'deliveryId': null},
      ];
      fake.overrides['GET /api/sales/certificates/71'] = (_) => jsonResp({...fake.certs.last, 'orderLineId': null, 'productId': 8});
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Pronto para expedir'), findsOneWidget);
    });

    testWidgets('a planned delivery that covers the balance turns "Programar entrega" into "Expedir ENT 15"', (tester) async {
      final fake = MoreFake();
      fake.order
        ..['status'] = 'Released'
        ..['ready'] = true
        ..['certificateWaived'] = true
        ..['deliveries'] = [
          {'id': 15, 'reference': 'ENT 15', 'plannedDate': '2026-10-28', 'status': 'Planned', 'packages': 1},
        ];
      ((fake.order['lines'] as List).first as Map<String, dynamic>)['planned'] = 100;
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Expedir ENT 15'), findsOneWidget);
      expect(find.text('Programar entrega'), findsNothing);
      await tapKey(tester, 'order-ship-delivery');
      expect(fake.called('GET', '/api/sales/deliveries/15'), isTrue);
    });

    testWidgets('credit above the limit is a banner on the order', (tester) async {
      final fake = MoreFake();
      fake.order
        ..['status'] = 'Released'
        ..['credit'] = {'limit': 5000, 'open': 10500, 'receivable': 300, 'thisOrder': 0, 'exceeded': true, 'limitSource': 'customer'};
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.byKey(const ValueKey('order-credit-banner')), findsOneWidget);
      expect(find.textContaining('passam do limite de R\$ 5.000,00 do cliente'), findsOneWidget);
    });

    testWidgets('no banner within the limit', (tester) async {
      final fake = MoreFake();
      fake.order['status'] = 'Released';
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.byKey(const ValueKey('order-credit-banner')), findsNothing);
    });

    testWidgets('the NF owed shows on the order header and in the deliveries table', (tester) async {
      final fake = MoreFake();
      fake.order
        ..['status'] = 'Shipped'
        ..['deliveries'] = [
          {'id': 15, 'reference': 'ENT 15', 'plannedDate': '2026-10-28', 'status': 'Shipped', 'packages': 1, 'invoiceNumber': null, 'needsInvoice': true},
        ];
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('NF pendente'), findsWidgets);
    });

    testWidgets('printing the NF of a delivery without a number is not offered; a failing print says so', (tester) async {
      final fake = MoreFake();
      fake.order
        ..['status'] = 'Shipped'
        ..['deliveries'] = [
          {'id': 15, 'reference': 'ENT 15', 'plannedDate': '2026-10-28', 'status': 'Shipped', 'packages': 1, 'invoiceNumber': null},
          {'id': 16, 'reference': 'ENT 16', 'plannedDate': '2026-10-29', 'status': 'Shipped', 'packages': 1, 'invoiceNumber': '1234'},
        ];
      fake.overrides['GET /api/sales/deliveries/16'] = (_) => http.Response('{"detail":"fora do ar"}', 500, headers: {'content-type': 'application/json'});
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('doc-print-nf-15'))).onPressed, isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('doc-print-nf-16')));
      await tapKey(tester, 'doc-print-nf-16');
      expect(find.textContaining('Falha ao imprimir a NF'), findsOneWidget);
    });

    testWidgets('only who may ship sees the confirm buttons on "Tudo expedido"', (tester) async {
      MoreFake shipped() => MoreFake()
        ..order['status'] = 'Shipped'
        ..order['deliveries'] = [
          {'id': 15, 'reference': 'ENT 15', 'plannedDate': '2026-10-28', 'status': 'Shipped', 'packages': 1, 'invoiceNumber': '1'},
        ];
      await pumpMore(tester, shipped(), (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.byKey(const ValueKey('order-confirm-delivery-15')), findsOneWidget);
      await pumpMore(tester, shipped(), (s) => SalesOrderScreen(session: s, id: 9), role: 'Reader');
      expect(find.byKey(const ValueKey('order-confirm-delivery-15')), findsNothing);
      expect(find.textContaining('Aguardando a confirmação'), findsOneWidget);
    });

    testWidgets('a partly shipped order cannot be cancelled from the menu: it points at "Encerrar saldo"', (tester) async {
      final fake = MoreFake();
      fake.order['status'] = 'PartiallyShipped';
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapKey(tester, 'order-menu');
      expect(find.byKey(const ValueKey('order-cancel-disabled')), findsOneWidget);
      expect(find.textContaining('Já houve expedição: use "Encerrar saldo"'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-cancel-disabled')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(fake.called('GET', '/api/sales/orders/9/cancel-preview'), isFalse);
    });
  });

  group('delivery dialog quantities', () {
    testWidgets('2,3 - 2,0 leaves 0,3 and typing 0,3 passes', (tester) async {
      final fake = MoreFake();
      fake.order['status'] = 'Released';
      ((fake.order['lines'] as List).first as Map<String, dynamic>)
        ..['quantity'] = 2.3
        ..['remaining'] = 2.3
        ..['planned'] = 2.0
        ..['available'] = 5;
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapKey(tester, 'order-deliver');
      if (find.byKey(const ValueKey('gate-skip')).evaluate().isNotEmpty) await tapKey(tester, 'gate-skip');
      await tester.enterText(find.byKey(const ValueKey('dl-qty-40')), '0,3');
      await tapKey(tester, 'delivery-ok');
      expect(find.textContaining('passa do saldo'), findsNothing);
      expect(fake.body(fake.last('POST', '/api/sales/orders/9/deliveries'))['lines'], [
        {'orderLineId': 40, 'quantity': 0.3},
      ]);
    });

    testWidgets('prefill is the smaller of the balance and the available; nothing available warns and starts empty', (tester) async {
      final fake = MoreFake();
      fake.order['status'] = 'Released';
      ((fake.order['lines'] as List).first as Map<String, dynamic>)['available'] = 0;
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapKey(tester, 'order-deliver');
      if (find.byKey(const ValueKey('gate-skip')).evaluate().isNotEmpty) await tapKey(tester, 'gate-skip');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('dl-qty-40'))).controller!.text, '');
      expect(find.textContaining('nenhum produto pronto'), findsOneWidget);
      await tapKey(tester, 'delivery-ok');
      expect(find.textContaining('Nenhum item tem produto acabado disponível'), findsOneWidget);
      expect(fake.called('POST', '/api/sales/orders/9/deliveries'), isFalse);
    });
  });

  group('print panel', () {
    testWidgets('papers that do not apply are left out of the total', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrintPanel(
              docs: [
                PrintDoc(id: 'a', label: 'A', onPrint: () async {}),
                const PrintDoc(id: 'b', label: 'B', ready: false, notApplicable: true),
                const PrintDoc(id: 'c', label: 'C', ready: false, waiting: 'falta'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('(1 de 2 prontos'), findsOneWidget);
    });
  });

  group('Painel numbers', () {
    http.Response page(List<Map<String, dynamic>> items, [int? total]) => jsonResp({'items': items, 'total': total ?? items.length, 'skip': 0, 'take': 200});

    ApiClient api(Map<String, http.Response Function(http.Request)> routes) => ApiClient(
      baseUrl: 'http://api.test',
      token: 't',
      client: MockClient((r) async {
        final route = routes[r.url.path];
        if (route != null) return route(r);
        if (r.url.path == '/api/sales/pipeline') return jsonResp({'kpis': {}, 'stages': []});
        return page([]);
      }),
    );

    test('deliveries without NF, shipped awaiting confirmation and overdue duplicatas are counted', () async {
      final d = await fetchCommercial(
        api({
          '/api/sales/deliveries': (r) => r.url.queryParameters['pendingInvoice'] == 'true'
              ? page([
                  {'id': 1, 'needsInvoice': true},
                  {'id': 2, 'needsInvoice': true},
                ], 7)
              : page([], 4),
          '/api/receivables': (r) => page([], 3),
        }),
      );
      expect(d.pendingInvoice, 7); // every row owes an NF: the server filtered, its total counts
      expect(d.shippedAwaiting, 4);
      expect(d.overdueReceivables, 3);
    });

    test('a server that ignores the filter and sends no flag does not raise a false alarm', () async {
      final d = await fetchCommercial(
        api({
          '/api/sales/deliveries': (_) => page([
            {'id': 1},
            {'id': 2},
          ]),
        }),
      );
      expect(d.pendingInvoice, 0);
    });
  });

  group('certificate editor', () {
    testWidgets('naming the rows still blank is covered in certificates_more_test; the helper message lists them', (tester) async {
      expect(foundRowsMessage(['C', 'LR']), contains('Faltam: C, LR'));
    });
  });
}
