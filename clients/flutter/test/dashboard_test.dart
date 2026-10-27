import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/shell.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> page(List<Map<String, dynamic>> items) => {'items': items, 'total': items.length, 'skip': 0, 'take': 50};

const lists = {'/api/stock/closings', '/api/purchasing/overdue', '/api/production/outside-shipments', '/api/production/load'};

final stopped = {
  'id': 7,
  'reference': 'OF-7',
  'productId': 1,
  'productCode': 'T-100',
  'productName': 'Tubo',
  'quantity': 10,
  'dueDate': '2099-01-01',
  'status': 'Stopped',
  'kind': 'Normal',
};

void main() {
  testWidgets('empty engineering shows a call to action, alert tile opens filtered orders, F5 refreshes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final log = <http.Request>[];
    final client = MockClient((r) async {
      log.add(r);
      final p = r.url.path;
      if (lists.contains(p)) return json([]);
      if (p == '/api/production/orders') return json(page(r.url.queryParameters['status'] == 'Created' ? [] : [stopped]));
      return json(page([]));
    });
    final session =
        Session(
            api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'),
          )
          ..username = 'pcp'
          ..role = 'Production';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Shell(session: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nenhum produto cadastrado'), findsOneWidget);
    expect(find.text('Cadastrar produtos'), findsOneWidget);
    expect(find.text('Nenhum local de estoque'), findsOneWidget);
    expect(find.textContaining('Atualizado às'), findsOneWidget);

    final before = log.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(log.length, greaterThan(before));

    await tester.tap(find.text('OFs paradas'));
    await tester.pumpAndSettle();
    expect(log.last.url.path, '/api/production/orders');
    expect(log.last.url.queryParameters['status'], 'Stopped');
    expect(find.text('OF-7'), findsOneWidget);
  });
}
