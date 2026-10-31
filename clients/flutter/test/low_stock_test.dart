import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/low_stock.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  testWidgets('low stock lists materials under the minimum and drafts requisitions in one click', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final log = <http.Request>[];
    final rows = [
      {
        'materialId': 4, 'code': 'BOB-15', 'description': 'Bobina 1,5mm', 'stockUnit': 'KG', 'purchaseUnit': 'KG', 'onHand': 40, 'minStock': 100, 'maxStock': 300,
        'incoming': 0, 'missing': 60, 'suggestedStock': 260, 'suggestedPurchase': 260, 'hasOpenRequisition': false, 'purchasable': true,
      },
    ];
    final client = MockClient((r) async {
      log.add(r);
      if (r.method == 'POST') return _json({'requisitionIds': [9], 'skipped': []});
      return _json(rows);
    });
    final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
      ..username = 'est'
      ..role = 'Stock'
      ..permissions = rolePermissions['Stock']!;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: LowStockScreen(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('BOB-15'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('low-stock-draft-all')));
    await tester.pumpAndSettle();
    final post = log.firstWhere((r) => r.method == 'POST');
    expect(post.url.path, '/api/stock/low-stock/requisitions');
    expect(jsonDecode(post.body)['materialIds'], [4]);
    expect(find.textContaining('1 requisição(ões) criada(s)'), findsOneWidget);
  });
}
