import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/suppliers.dart';
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

const _supplier = {'id': 1, 'name': 'Aços Sul', 'tradeName': 'Sul', 'legacyCode': '77', 'groupCode': null, 'active': true, 'addressCount': 1};

Map<String, dynamic> _performance({int received = 20, double pct = 95}) => {
  'onTimePercent': pct, 'receivedLines': received, 'onTimeLines': 19, 'averageDaysLate': 1.5, 'overdueLines': 2,
  'orders': 8, 'openOrders': 3, 'orderedValue': 1000, 'receipts': 6, 'receivedValue': 900,
};

Future<List<http.Request>> _pump(WidgetTester tester, Widget Function(Session) screen, {String role = 'Admin', Map<String, dynamic> Function()? performance}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    final path = r.url.path;
    if (path == '/api/suppliers/1/performance') return _json((performance ?? _performance)());
    if (path == '/api/suppliers/1/materials') {
      return _json(_page([
        {'materialId': 4, 'materialCode': 'BOB-15', 'materialDescription': 'Bobina 1,5mm', 'qualification': 'A', 'qualifiedAt': '2026-01-10', 'lastUnitPrice': 5.5, 'lastPurchaseDate': '2026-09-01', 'notes': null},
      ]));
    }
    if (r.method == 'POST' || r.method == 'PUT') return _json({..._supplier, 'id': 2, 'name': 'Novo'});
    if (path == '/api/suppliers') return _json(_page([_supplier]));
    return _json(_page([]));
  });
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
    ..username = 'u'
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
  return log;
}

void main() {
  testWidgets('supplier list opens the supplier with performance, materials and other tabs', (tester) async {
    final log = await _pump(tester, (s) => SuppliersScreen(session: s));
    expect(find.text('Aços Sul'), findsOneWidget);
    expect(find.text('Novo'), findsOneWidget);
    await tester.tap(find.text('Aços Sul'));
    await tester.pumpAndSettle();
    expect(find.text('Pontualidade'), findsOneWidget);
    expect(find.text('95,0 %'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    await tester.tap(find.text('3m'));
    await tester.pumpAndSettle();
    expect(log.where((r) => r.url.path == '/api/suppliers/1/performance').length, 2);
    await tester.tap(find.text('Materiais'));
    await tester.pumpAndSettle();
    expect(find.text('BOB-15'), findsOneWidget);
    for (final tab in ['Atrasos', 'Pedidos', 'Recebimentos']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }
  });

  for (final c in [(75.0, 20, '75,0 %'), (40.0, 20, '40,0 %'), (0.0, 0, '0,0 %')]) {
    testWidgets('performance view shows ${c.$3} with ${c.$2} received lines', (tester) async {
      await _pump(tester, (s) => PerformanceView(session: s, supplierId: 1), performance: () => _performance(received: c.$2, pct: c.$1));
      expect(find.text(c.$3), findsOneWidget);
    });
  }

  testWidgets('new supplier form posts to the API', (tester) async {
    final log = await _pump(tester, (s) => SuppliersScreen(session: s));
    await tester.tap(find.text('Novo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-name')), 'Novo');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(log.any((r) => r.method == 'POST' && r.url.path == '/api/suppliers'), isTrue);
  });

  testWidgets('read-only role gets no new-supplier button and edits nothing in the material tab', (tester) async {
    await _pump(tester, (s) => SuppliersScreen(session: s), role: 'Reader');
    expect(find.text('Novo'), findsNothing);
    await tester.tap(find.text('Aços Sul'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Materiais'));
    await tester.pumpAndSettle();
    expect(find.text('Vincular material'), findsNothing);
    await tester.tap(find.text('BOB-15'));
    await tester.pumpAndSettle();
  });
}
