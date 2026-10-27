import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart' show appTheme;
import 'package:ebt_engenharia/screens/shell.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/alerts.dart';
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

Future<(Session, List<http.Request>)> pumpShell(
  WidgetTester tester,
  String role, {
  Size size = const Size(1600, 1400),
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
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
    if (p == '/api/production/orders') return json(page(r.url.queryParameters['status'] == 'Created' ? [] : [stopped]));
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
  return (session, log);
}

Future<void> openPalette(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('onboarding card replaces empty sections, alert tile opens filtered orders, F5 refreshes', (tester) async {
    final (_, log) = await pumpShell(tester, 'Production');
    expect(find.text('Primeiros passos'), findsOneWidget);
    expect(find.text('Cadastrar produtos'), findsOneWidget);
    expect(find.text('Nenhum local de estoque'), findsNothing);
    expect(find.text('Estoque'), findsWidgets);
    expect(find.textContaining('Atualizado às'), findsOneWidget);
    final card = find.ancestor(of: find.text('Primeiros passos'), matching: find.byType(Card)).first;
    expect(tester.getSize(card).width, lessThanOrEqualTo(1280));

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

  testWidgets('empty sections are hidden and their tabs removed', (tester) async {
    await pumpShell(tester, 'Production');
    final tabs = find.byWidgetPredicate((w) => w is InkWell && w.key is GlobalKey);
    expect(tabs, findsNWidgets(2));
    expect(find.descendant(of: tabs, matching: find.text('PCP')), findsOneWidget);
    expect(find.descendant(of: tabs, matching: find.text('Estoque')), findsNothing);
  });

  testWidgets('bell shows the Atenção total and jumps to the filtered list', (tester) async {
    final (_, log) = await pumpShell(tester, 'Production');
    expect(find.byTooltip('Notificações (1)'), findsOneWidget);
    await tester.tap(find.byTooltip('Notificações (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(PopupMenuItem<AlertInfo>), matching: find.text('OFs paradas')));
    await tester.pumpAndSettle();
    expect(log.last.url.queryParameters['status'], 'Stopped');
  });

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
    await tester.tap(find.byTooltip('Recolher menu'));
    await tester.pumpAndSettle();
    expect(find.text('Saldos'), findsNothing);
    await tester.tap(find.byTooltip('Saldos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expandir menu'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Saldos')).selected, isTrue);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Painel')).selected, isFalse);
  });

  testWidgets('collapsed state is restored', (tester) async {
    await pumpShell(tester, 'Admin', prefs: {'navCollapsed': true});
    expect(find.text('Saldos'), findsNothing);
    expect(find.byTooltip('Expandir menu'), findsOneWidget);
  });

  testWidgets('sidebar groups collapse and the choice is remembered', (tester) async {
    await pumpShell(tester, 'Admin');
    expect(find.text('Saldos'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(ExpansionTile), matching: find.text('Estoque')));
    await tester.pumpAndSettle();
    expect(find.text('Saldos'), findsNothing);
    final p = await SharedPreferences.getInstance();
    expect(p.getStringList('navClosedGroups'), ['Estoque']);
    await pumpShell(
      tester,
      'Admin',
      prefs: {
        'navClosedGroups': <String>['Estoque'],
      },
    );
    expect(find.text('Saldos'), findsNothing);
    expect(find.text('Movimentações'), findsNothing);
    expect(find.text('Funil de vendas'), findsOneWidget);
  });

  testWidgets('command palette: keyboard navigation, actions, products and recents', (tester) async {
    final (_, log) = await pumpShell(tester, 'Admin');
    await openPalette(tester);
    expect(find.text('Nova OF'), findsWidgets);
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), 'saldo');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Saldos')).selected, isTrue);

    await openPalette(tester);
    expect(find.text('Recentes'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), 'nova req');
    await tester.pumpAndSettle();
    expect(find.text('Ações'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Nova requisição'), findsWidgets);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await openPalette(tester);
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), 'T-1');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('T-100  Tubo 25x1,5'), findsOneWidget);
    expect(log.any((r) => r.url.path == '/api/products' && r.url.queryParameters['q'] == 'T-1'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('avatar menu: profile, theme and sign out', (tester) async {
    final (session, _) = await pumpShell(tester, 'Admin');
    await tester.tap(find.byTooltip('Conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Usuário: ana'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tema escuro'));
    await tester.pumpAndSettle();
    expect(session.themeMode, ThemeMode.dark);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('themeMode'), 'dark');
  });

  testWidgets('section tabs scroll and follow the scroll position', (tester) async {
    await pumpShell(tester, 'Production', size: const Size(1600, 500));
    final tab = find.descendant(of: find.byWidgetPredicate((w) => w is InkWell && w.key is GlobalKey), matching: find.text('PCP'));
    TextStyle? style() => tester.widget<Text>(tab).style;
    expect(style()?.fontWeight, FontWeight.w400);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(style()?.fontWeight, FontWeight.w600);
    final scrollable = find.ancestor(of: find.text('OFs a liberar'), matching: find.byType(Scrollable)).first;
    await tester.drag(scrollable, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(style()?.fontWeight, FontWeight.w400);
  });

  test('cards use a higher-contrast surface and an outline', () {
    for (final b in Brightness.values) {
      final t = appTheme(b);
      expect(t.cardTheme.color, t.colorScheme.surfaceContainerHigh);
      expect((t.cardTheme.shape as RoundedRectangleBorder).side.color, t.colorScheme.outlineVariant);
    }
  });
}
