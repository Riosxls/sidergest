// Shared fake API and pump helper for sales_quotes_more_test.dart and sales_orders_more_test.dart.
import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response jsonResp(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> pageOf(List<Map<String, dynamic>> items) => {'items': items, 'total': items.length, 'skip': 0, 'take': 50};

Map<String, dynamic> defaultQuote() => {
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
  'validUntil': null,
  'conditions': 'Faturamento mínimo R\$ 300',
  'notes': null,
  'status': 'Draft',
  'needsApproval': false,
  'approvedBy': null,
  'approvedAt': null,
  'sentAt': null,
  'sentTo': null,
  'decidedAt': null,
  'decisionBy': null,
  'decisionNote': null,
  'customerPo': null,
  'requestText': null,
  'requestFileName': null,
  'requestFileSize': null,
  'salesOrderId': null,
  'salesOrderReference': null,
  'createdBy': 'ana',
  'createdAt': '2026-10-25T12:00:00Z',
  'lostReason': null,
  'supersededById': null,
  'supersededBy': null,
  'totals': {'products': 10900, 'ipi': 500, 'icms': 1800, 'total': 11400, 'maxDiscountPercent': 0},
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
  'history': [
    {'id': 1, 'action': 'created', 'fromStatus': null, 'toStatus': 'Draft', 'note': null, 'user': 'ana', 'at': '2026-10-25T12:00:00Z'},
  ],
};

Map<String, dynamic> defaultOrder() => {
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
  'billTo': 'Ebt',
  'origin': 'Email',
  'salesperson': 'ana',
  'status': 'Created',
  'statusReason': null,
  'notes': null,
  'certificateWaived': false,
  'quoteId': 5,
  'quoteReference': 'PROP 31',
  'createdBy': 'ana',
  'createdAt': '2026-10-26T12:00:00Z',
  'releasedBy': null,
  'releasedAt': null,
  'products': 10000,
  'ipi': 500,
  'total': 10500,
  'progress': 0.3,
  'ready': false,
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
      'fromStock': 0,
      'productionOrderId': null,
      'productionReference': null,
      'productionStatus': null,
      'produced': 0,
      'shipped': 0,
      'planned': 0,
      'remaining': 100,
      'available': 30,
      'ready': false,
      'spec': {'outsideDiameter': 25.4, 'thickness': 1.5, 'length': 6000, 'standard': 'NBR 5599', 'condition': 'Trefilado', 'materialNeedKg': 120},
    },
  ],
  'deliveries': <Map<String, dynamic>>[],
  'history': [
    {'id': 1, 'action': 'created', 'fromStatus': null, 'toStatus': 'Created', 'note': null, 'user': 'ana', 'at': '2026-10-26T12:00:00Z'},
  ],
};

/// A fake API for the quote and order screens. Mutate [quote] / [order] before or during a test; action endpoints answer with the current maps
/// after applying the status in [quoteAfter] / [orderAfter] (keyed by the last path segment).
class MoreFake {
  final log = <http.Request>[];
  Map<String, dynamic> quote = defaultQuote();
  Map<String, dynamic> order = defaultOrder();
  List<Map<String, dynamic>> certs = [];
  final Map<String, String> quoteAfter = {
    'send': 'Sent',
    'approve': 'Sent',
    'reject-approval': 'Draft',
    'reopen': 'Draft',
    'extend': 'Sent',
    'accept': 'Accepted',
    'decline': 'Rejected',
    'cancel': 'Cancelled',
    'purchase-order': 'PurchaseOrder',
  };
  final Map<String, String> orderAfter = {'release': 'Released', 'cancel': 'Cancelled', 'close-balance': 'Shipped'};

  /// Per-route override: key is `METHOD path`; return null to fall through to the default answer.
  final Map<String, http.Response Function(http.Request r)> overrides = {};
  Map<String, dynamic>? credit;
  Map<String, dynamic> settings = {'maxDiscountPercent': 5, 'defaultValidityDays': 15, 'minimumOrderValue': 0, 'offListNeedsApproval': false};
  num listPrice = 100;

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  Iterable<http.Request> where(String method, String path) => log.where((r) => r.method == method && r.url.path == path);

  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);

  bool called(String method, String path) => where(method, path).isNotEmpty;

  /// Same as [overrides] for a route that must answer later (a test holds the request in flight).
  final Map<String, Future<http.Response> Function(http.Request r)> asyncOverrides = {};

  MockClient get client => MockClient((r) async {
    final later = asyncOverrides['${r.method} ${r.url.path}'];
    if (later != null) {
      log.add(r);
      return later(r);
    }
    return answer(r);
  });

  http.Response answer(http.Request r) {
    log.add(r);
    final p = r.url.path;
    final m = r.method;
    final o = overrides['$m $p'];
    if (o != null) return o(r);
    final seg = p.split('/').last;
    if (p == '/api/sales/settings') return jsonResp(settings);
    if (p == '/api/sales/price') return jsonResp({'productId': 7, 'unitPrice': listPrice});
    if (p == '/api/sales/quotes' && m == 'POST') return jsonResp({...quote, 'id': 5}, 201);
    if (p == '/api/sales/quotes' && m == 'GET') return jsonResp(pageOf([_quoteRow(quote)]));
    if (p == '/api/sales/quotes/5/credit') return jsonResp(credit ?? {'limit': null, 'open': 0, 'thisOrder': 11400, 'exceeded': false});
    if (p == '/api/sales/quotes/5/request-file' && m == 'GET') return http.Response.bytes([1, 2, 3], 200);
    if (p == '/api/sales/quotes/5/convert') {
      quote['status'] = 'Converted';
      quote['salesOrderId'] = 9;
      return jsonResp(order, 201);
    }
    if (p == '/api/sales/quotes/5/duplicate') return jsonResp({...quote, 'id': 6, 'reference': 'PROP 32', 'status': 'Draft'}, 201);
    if (p == '/api/sales/quotes/5/revise') return jsonResp({...quote, 'id': 8, 'reference': 'PROP 31A', 'revision': 1, 'status': 'Draft'}, 201);
    if (p == '/api/sales/quotes/5/request') {
      quote['requestText'] = body(r)['text'];
      return jsonResp(quote);
    }
    if (p == '/api/sales/quotes/5/request-file' && m == 'DELETE') {
      quote['requestFileName'] = null;
      return jsonResp(quote);
    }
    if (p.startsWith('/api/sales/quotes/5/') && m == 'POST' && quoteAfter.containsKey(seg)) {
      quote['status'] = quoteAfter[seg];
      return jsonResp(quote);
    }
    if (p == '/api/sales/quotes/5' && m == 'PUT') return jsonResp({...quote, ...body(r)});
    if (p == '/api/sales/quotes/5' && m == 'DELETE') return http.Response('', 204);
    if (p == '/api/sales/quotes/5') return jsonResp(quote);
    if (p == '/api/sales/quotes/8' || p == '/api/sales/quotes/6') return jsonResp({...quote, 'id': int.parse(seg), 'reference': 'PROP 31A', 'status': 'Draft'});
    if (p == '/api/sales/orders' && m == 'POST') return jsonResp({...order, 'id': 9}, 201);
    if (p == '/api/sales/orders' && m == 'GET') return jsonResp(pageOf([_orderRow(order)]));
    if (p == '/api/sales/orders/9/cancel-preview') {
      return jsonResp({'plannedDeliveries': <String>[], 'shippedDeliveries': <String>[], 'productionOrders': <Map<String, dynamic>>[], 'reservations': 0});
    }
    if (p == '/api/sales/orders/9/certificate-waiver') {
      order['certificateWaived'] = body(r)['waived'];
      return jsonResp(order);
    }
    if (p == '/api/sales/orders/9/deliveries') return jsonResp(_delivery(), 201);
    if (p.startsWith('/api/sales/orders/9/') && m == 'POST') {
      if (orderAfter.containsKey(seg)) order['status'] = orderAfter[seg];
      return jsonResp(order);
    }
    if (p == '/api/sales/orders/9' && m == 'PUT') return jsonResp({...order, ...body(r)});
    if (p == '/api/sales/orders/9') return jsonResp(order);
    if (p == '/api/sales/deliveries/15') return jsonResp(_delivery());
    if (p == '/api/sales/certificates') return jsonResp(pageOf(certs));
    if (p == '/api/customers/2/addresses') {
      return jsonResp([
        {'id': 3, 'street': 'Av. Brasil', 'number': '100', 'city': 'Embu', 'uf': 'SP', 'buyer': 'Edilto', 'email': 'compras@bts.com'},
        {'id': 4, 'street': 'Rua B', 'number': '5', 'city': 'Cotia', 'uf': 'SP', 'buyer': 'Marta', 'email': 'marta@bts.com'},
      ]);
    }
    if (p == '/api/customers/2') {
      return jsonResp({
        'id': 2,
        'name': 'BTS Tubos',
        'company': {'paymentTermId': 1, 'paymentTermName': '28 DDL'},
      });
    }
    if (p == '/api/customers') {
      return jsonResp(
        pageOf([
          {'id': 2, 'name': 'BTS Tubos'},
        ]),
      );
    }
    if (p == '/api/sales/payment-terms') {
      return jsonResp(
        pageOf([
          {'id': 1, 'code': 1, 'name': '28 DDL', 'days': 28},
        ]),
      );
    }
    if (p == '/api/products') {
      return jsonResp(
        pageOf([
          {'id': 7, 'code': 'TB-25', 'description': 'Tubo 25,4 x 1,5'},
        ]),
      );
    }
    if (p == '/api/viability') return jsonResp(pageOf([]));
    return jsonResp(pageOf([]));
  }

  Map<String, dynamic> _delivery() => {
    'id': 15,
    'number': 15,
    'reference': 'ENT 15',
    'orderId': 9,
    'orderReference': 'PV 9',
    'customerId': 2,
    'customerName': 'BTS Tubos',
    'addressText': 'Av. Brasil, 100',
    'plannedDate': '2026-10-28',
    'status': 'Planned',
    'carrier': 'Próprio',
    'packages': 1,
    'grossWeightKg': 85.5,
    'createdBy': 'ana',
    'createdAt': '2026-10-26T12:00:00Z',
    'lines': <Map<String, dynamic>>[],
    'history': <Map<String, dynamic>>[],
  };

  Map<String, dynamic> _quoteRow(Map<String, dynamic> q) => {
    'id': q['id'],
    'reference': q['reference'],
    'customerName': q['customerName'],
    'status': q['status'],
    'revision': q['revision'],
    'total': 11400,
    'validUntil': q['validUntil'],
    'createdAt': q['createdAt'],
    'createdBy': q['createdBy'],
    'needsApproval': q['needsApproval'],
    'followUp': false,
    'expiring': false,
  };

  Map<String, dynamic> _orderRow(Map<String, dynamic> o) => {
    'id': o['id'],
    'reference': o['reference'],
    'customerName': o['customerName'],
    'customerPo': o['customerPo'],
    'status': o['status'],
    'billTo': 'Ebt',
    'total': 10500,
    'balanceValue': 5000,
    'balanceKg': 80,
    'nextDue': '2026-11-15',
    'progress': 0.5,
    'late': o['late'],
    'ready': o['ready'],
  };
}

Future<Session> pumpMore(WidgetTester tester, MoreFake fake, Widget Function(Session s) screen, {String role = 'Sales', Size size = const Size(1700, 1800)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: fake.client, token: 'tok'))
    ..username = 'ana'
    ..role = role
    ..permissions = rolePermissions[role]!;
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

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester, String key, String item) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}
