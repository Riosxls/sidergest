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

  Future<List<http.Request>> pumpShell(WidgetTester tester, String role, {Size size = const Size(1600, 1400), Map<String, dynamic>? prefs}) async {
    SharedPreferences.setMockInitialValues({...?prefs});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final log = <http.Request>[];
    final client = MockClient((r) async {
      log.add(r);
      final p = r.url.path;
      if (lists.contains(p)) return json([]);
      if (p == '/api/products' && r.url.queryParameters['q'] == 'T-1') {
        return json(
          page([
            {'id': 1, 'code': 'T-100', 'name': 'Tubo 25x1,5'},
          ]),
        );
      }
      return json(page([]));
    });
    final session =
        Session(
            api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'),
          )
          ..username = 'ana'
          ..role = role;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Shell(session: session),
      ),
    );
    await tester.pumpAndSettle();
    return log;
  }

  testWidgets('quick actions follow the role', (tester) async {
    await pumpShell(tester, 'Production');
    expect(find.text('Nova OF'), findsOneWidget);
    expect(find.text('Novo pedido'), findsNothing);
    expect(find.text('Novo produto'), findsNothing);
  });

  testWidgets('admin quick actions open the creation forms', (tester) async {
    await pumpShell(tester, 'Admin');
    for (final l in ['Novo produto', 'Nova OF', 'Nova requisição', 'Novo pedido']) {
      expect(find.text(l), findsOneWidget);
    }
    await tester.tap(find.text('Nova OF'));
    await tester.pumpAndSettle();
    expect(find.text('Nova ordem de fabricação'), findsOneWidget);
  });

  testWidgets('sidebar collapses to icons, remembers it, and marks the active page', (tester) async {
    await pumpShell(tester, 'Admin');
    expect(find.text('Saldos'), findsOneWidget);
    await tester.tap(find.byTooltip('Recolher menu'));
    await tester.pumpAndSettle();
    expect(find.text('Saldos'), findsNothing);
    expect(find.byTooltip('Saldos'), findsOneWidget);
    await tester.tap(find.byTooltip('Saldos'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expandir menu'), findsOneWidget);
    await tester.tap(find.byTooltip('Expandir menu'));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Saldos'));
    expect(tile.selected, isTrue);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Painel')).selected, isFalse);
  });

  testWidgets('collapsed state is restored', (tester) async {
    await pumpShell(tester, 'Admin', prefs: {'navCollapsed': true});
    expect(find.text('Saldos'), findsNothing);
    expect(find.byTooltip('Expandir menu'), findsOneWidget);
  });

  testWidgets('global search finds screens and products and opens them', (tester) async {
    final log = await pumpShell(tester, 'Admin');
    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'saldo');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Saldos').last);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Saldos')).selected, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'T-1');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('T-100  Tubo 25x1,5'), findsOneWidget);
    expect(log.any((r) => r.url.path == '/api/products' && r.url.queryParameters['q'] == 'T-1'), isTrue);
  });

  testWidgets('section shortcuts scroll the dashboard', (tester) async {
    await pumpShell(tester, 'Admin', size: const Size(1600, 500));
    final seg = find.descendant(of: find.byType(SegmentedButton<int>), matching: find.text('PCP'));
    expect(seg, findsOneWidget);
    final before = tester.getTopLeft(find.text('Nenhuma OF aberta')).dy;
    await tester.tap(seg);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Nenhuma OF aberta')).dy, lessThan(before));
  });
}
