import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:ebt_engenharia/screens/steel.dart';
import 'package:ebt_engenharia/screens/viability.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> study({String status = 'InReview', bool quality = false}) => {
  'id': 5,
  'number': 5,
  'reference': 'FAV 5',
  'quoteId': 31,
  'quoteReference': 'PROP 31',
  'customerId': 1,
  'customerName': 'BTS Tubos',
  'productId': 3,
  'productCode': 'TB-50',
  'productName': 'Tubo 50x50',
  'title': 'Tubo Ø25,4 x 1,5',
  'characteristics': 'DIN 2393',
  'transformations': 'Corte + furação',
  'finishing': null,
  'packaging': 'Fardo',
  'monthlyConsumptionKg': 800,
  'status': status,
  'rejectionReason': null,
  'ordersAllowed': 3,
  'ordersUsed': 1,
  'ordersRemaining': 2,
  'signoffs': [
    {'area': 'Quality', 'by': quality ? 'eng' : null, 'at': quality ? '2026-10-27T10:00:00Z' : null, 'note': null},
    {'area': 'Production', 'by': 'pcp', 'at': '2026-10-27T09:00:00Z', 'note': 'Ok'},
    {'area': 'Commercial', 'by': null, 'at': null, 'note': null},
  ],
  'orders': [
    {'orderId': 9, 'reference': 'PV 9', 'status': 'Released'},
  ],
  'createdBy': 'ana',
  'createdAt': '2026-10-26T10:00:00Z',
  'history': [
    {'id': 1, 'action': 'submitted', 'fromStatus': 'Draft', 'toStatus': 'InReview', 'note': null, 'user': 'ana', 'at': '2026-10-26T11:00:00Z'},
  ],
};

final lot = {
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
  'returnedKg': 0,
  'scrapKg': 0,
  'usedKg': 0,
  'serviceCost': 0,
  'laborCost': 0,
  'balanceKg': 200,
  'balanceValue': 1200,
  'totalCost': 6000,
  'pendingJobs': 1,
  'notes': null,
  'createdAt': '2026-10-01T10:00:00Z',
};

final job = {
  'id': 9,
  'lotId': 3,
  'lotCode': 'B-100',
  'processorId': 2,
  'processorName': 'Açoservice',
  'shipmentInvoice': 'N1',
  'shipmentDate': '2026-10-02',
  'sentKg': 800,
  'returnInvoice': null,
  'returnDate': null,
  'finishedKg': null,
  'scrapKg': null,
  'lossPercent': null,
  'serviceCost': null,
  'returned': false,
  'notes': null,
};

class Fake {
  final log = <http.Request>[];
  var role = 'Admin';
  var qualitySigned = false;

  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);
  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  late final client = MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    if (p == '/api/viability/5') {
      return json(study(quality: qualitySigned));
    }
    if (p == '/api/viability/5/sign/quality') {
      qualitySigned = true;
      return json(study(quality: true));
    }
    if (p == '/api/steel/lots/3') return json(lot);
    if (p == '/api/steel/lots/3/slitter') return json([job]);
    if (p == '/api/steel/lots/3/usages') return json([]);
    if (p == '/api/steel/slitter/9') return json({...job, 'returned': true});
    if (p == '/api/steel/lots') {
      return json({
        'items': [lot],
        'total': 1,
        'skip': 0,
        'take': 50,
      });
    }
    return json({'items': [], 'total': 0, 'skip': 0, 'take': 50});
  });
}

Future<(Session, Fake)> pump(WidgetTester tester, Fake fake, Widget Function(Session s) screen) async {
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
      home: screen(session),
    ),
  );
  await tester.pumpAndSettle();
  return (session, fake);
}

void main() {
  test('packSpec nests the measurement fields of an order line', () {
    final out = packSpec({'productId': 3, 'quantity': 10, 'outsideDiameter': 25.4, 'condition': 'Nbk', 'saleUnit': 'PC', 'feasibilityId': 5});
    expect(out['spec'], {'outsideDiameter': 25.4, 'condition': 'Nbk', 'saleUnit': 'PC'});
    expect(out.containsKey('outsideDiameter'), isFalse);
    expect(out['feasibilityId'], 5);
    expect(packSpec({'productId': 3}).containsKey('spec'), isFalse);
  });

  testWidgets('only the matching area can sign a feasibility study, and the sign-off is posted', (tester) async {
    final fake = Fake()..role = 'Engineering';
    await pump(tester, fake, (s) => FeasibilityScreen(session: s, id: 5));
    expect(find.text('FAV 5 · Tubo Ø25,4 x 1,5'), findsOneWidget);
    expect(find.text('Aguardando assinaturas · 1 de 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-Production')), findsNothing);
    expect(find.byKey(const ValueKey('sign-Commercial')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sign-Quality')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assinar').last);
    await tester.pumpAndSettle();
    expect(fake.log.any((r) => r.method == 'POST' && r.url.path == '/api/viability/5/sign/quality'), isTrue);
    expect(find.byKey(const ValueKey('sign-Quality')), findsNothing);
    expect(find.text('1 de 3 pedidos usados'), findsOneWidget);
  });

  testWidgets('a reader sees the study without sign-off buttons', (tester) async {
    final fake = Fake()..role = 'Reader';
    await pump(tester, fake, (s) => FeasibilityScreen(session: s, id: 5));
    expect(find.textContaining('Assinar'), findsNothing);
    expect(find.byKey(const ValueKey('fav-menu')), findsNothing);
  });

  testWidgets('steel lot shows balance and the slitter return is saved with the full job', (tester) async {
    final fake = Fake()..role = 'Stock';
    await pump(tester, fake, (s) => SteelLotScreen(session: s, id: 3));
    expect(find.text('B-100 · Usina Sul'), findsOneWidget);
    expect(find.text('Saldo (kg)'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('job-return-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('job-return-9')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-returnInvoice')), 'R9');
    await tester.enterText(find.byKey(const ValueKey('field-finishedKg')), '760');
    await tester.enterText(find.byKey(const ValueKey('field-scrapKg')), '30');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final sent = fake.body(fake.last('PUT', '/api/steel/slitter/9'));
    expect(sent['lotId'], 3);
    expect(sent['processorId'], 2);
    expect(sent['sentKg'], 800);
    expect(sent['returnInvoice'], 'R9');
    expect(sent['finishedKg'], 760);
    expect(sent['scrapKg'], 30);
  });

  testWidgets('steel tabs list lots, slitter jobs and usage', (tester) async {
    final fake = Fake()..role = 'Reader';
    await pump(tester, fake, (s) => Scaffold(body: SteelScreen(session: s)));
    expect(find.text('B-100'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-steel-lot')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('steel-tab-slitter')));
    await tester.pumpAndSettle();
    expect(fake.log.any((r) => r.url.path == '/api/steel/slitter'), isTrue);
    await tester.tap(find.byKey(const ValueKey('steel-tab-usage')));
    await tester.pumpAndSettle();
    expect(fake.log.any((r) => r.url.path == '/api/steel/usages'), isTrue);
  });
}
