import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart' show appTheme;
import 'package:ebt_engenharia/screens/shell.dart';
import 'package:ebt_engenharia/session.dart';
import 'role_permissions.dart';
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
    if (p == '/api/sales/pipeline') {
      return json({
        'kpis': {'openQuotes': 2, 'openOrders': 5, 'lateOrders': 1, 'readyToShip': 0, 'pendingApprovals': 0},
        'stages': [],
      });
    }
    if (p == '/api/production/orders') return json(page(r.url.queryParameters['status'] == 'Created' ? [] : [stopped]));
    return json(page([]));
  });
  final session =
      Session(
          api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'),
        )
        ..username = 'ana'
        ..role = role
        ..permissions = rolePermissions[role]!;
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
  backArrowTests();
  painelExtrasTests();
  testWidgets('Painel shows one card per module with metric and alert badge; no module content', (tester) async {
    final (_, log) = await pumpShell(tester, 'Production');
    expect(find.text('Primeiros passos'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-products')), findsNothing);
    await tester.tap(find.text('Primeiros passos'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('step-products')), findsOneWidget);
    expect(find.textContaining('Atualizado às'), findsOneWidget);
    for (final id in ['sales', 'engineering', 'stock', 'purchasing', 'production']) {
      expect(find.byKey(ValueKey('module-card-$id')), findsOneWidget);
    }
    expect(find.descendant(of: find.byKey(const ValueKey('module-card-sales')), matching: find.text('5')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('module-badge-sales')), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('module-badge-production')), matching: find.text('1')), findsOneWidget);
    expect(find.text('OFs paradas'), findsNothing);
    expect(find.text('Atenção'), findsNothing);
    final before = log.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(log.length, greaterThan(before));
  });

  testWidgets('module card opens a screen with only that module', (tester) async {
    final (_, log) = await pumpShell(tester, 'Admin');
    await tester.tap(find.byKey(const ValueKey('module-card-production')));
    await tester.pumpAndSettle();
    expect(find.text('OFs paradas'), findsOneWidget);
    expect(find.text('OFs em produção'), findsOneWidget);
    expect(find.text('Pedidos atrasados'), findsNothing);
    expect(find.text('Itens abaixo do mínimo'), findsNothing);
    expect(find.text('Nova Ordem de Fabricação'), findsOneWidget);
    expect(find.text('Novo pedido'), findsNothing);
    expect(find.text('Telas de PCP'), findsOneWidget);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Painel')).selected, isTrue);

    await tester.tap(find.text('OFs paradas'));
    await tester.pumpAndSettle();
    expect(log.last.url.queryParameters['status'], 'Stopped');
    expect(find.text('OF-7'), findsOneWidget);
  });

  testWidgets('module screen only fetches its own data and goes back to the Painel', (tester) async {
    final (_, log) = await pumpShell(tester, 'Admin');
    log.clear();
    await tester.tap(find.byKey(const ValueKey('module-card-sales')));
    await tester.pumpAndSettle();
    expect(find.text('Pedidos abertos'), findsOneWidget);
    expect(find.text('Propostas pendentes'), findsOneWidget);
    expect(find.text('Entregas atrasadas'), findsOneWidget);
    expect(log.every((r) => r.url.path.startsWith('/api/sales')), isTrue);
    await tester.tap(find.byTooltip('Voltar ao Painel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('module-card-stock')), findsOneWidget);
  });

  testWidgets('bell shows the Atenção total and jumps to the filtered list', (tester) async {
    final (_, log) = await pumpShell(tester, 'Production');
    expect(find.byTooltip('Notificações (2)'), findsOneWidget);
    await tester.tap(find.byTooltip('Notificações (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(PopupMenuItem<AlertInfo>), matching: find.text('OFs paradas')));
    await tester.pumpAndSettle();
    expect(log.last.url.queryParameters['status'], 'Stopped');
  });

  testWidgets('module quick actions follow the role', (tester) async {
    await pumpShell(tester, 'Production');
    await tester.tap(find.byKey(const ValueKey('module-card-production')));
    await tester.pumpAndSettle();
    expect(find.text('Nova Ordem de Fabricação'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar ao Painel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('module-card-purchasing')));
    await tester.pumpAndSettle();
    expect(find.text('Novo pedido'), findsNothing);
    expect(find.text('Nova Ordem de Fabricação'), findsNothing);
  });

  testWidgets('admin module quick actions open the creation forms', (tester) async {
    await pumpShell(tester, 'Admin');
    await tester.tap(find.byKey(const ValueKey('module-card-purchasing')));
    await tester.pumpAndSettle();
    for (final l in ['Nova requisição', 'Novo pedido']) {
      expect(find.text(l), findsOneWidget);
    }
    await tester.tap(find.byTooltip('Voltar ao Painel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('module-card-production')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova Ordem de Fabricação'));
    await tester.pumpAndSettle();
    expect(find.text('Nova ordem de fabricação'), findsOneWidget);
  });

  testWidgets('sidebar collapses to icons, remembers it, and marks the active page', (tester) async {
    await pumpShell(tester, 'Admin');
    await tester.tap(find.byTooltip('Recolher menu'));
    await tester.pumpAndSettle();
    expect(find.text('Relatórios'), findsNothing);
    await tester.tap(find.byTooltip('Parâmetros'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expandir menu'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Parâmetros')).selected, isTrue);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Painel')).selected, isFalse);
  });

  testWidgets('collapsed state is restored', (tester) async {
    await pumpShell(tester, 'Admin', prefs: {'navCollapsed': true});
    expect(find.text('Relatórios'), findsNothing);
    expect(find.byTooltip('Expandir menu'), findsOneWidget);
  });

  testWidgets('sidebar groups collapse and the choice is remembered', (tester) async {
    await pumpShell(tester, 'Admin');
    expect(find.text('Carteira de pedidos'), findsOneWidget);
    expect(find.text('Nenhum favorito ainda'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(ExpansionTile), matching: find.text('Relatórios')));
    await tester.pumpAndSettle();
    expect(find.text('Carteira de pedidos'), findsNothing);
    final p = await SharedPreferences.getInstance();
    expect(p.getStringList('navClosedGroups'), ['Relatórios']);
    await pumpShell(
      tester,
      'Admin',
      prefs: {
        'navClosedGroups': <String>['Relatórios'],
      },
    );
    expect(find.text('Carteira de pedidos'), findsNothing);
    expect(find.text('Parâmetros'), findsOneWidget);
  });

  testWidgets('command palette: keyboard navigation, actions, products and recents', (tester) async {
    final (_, log) = await pumpShell(tester, 'Admin');
    await openPalette(tester);
    expect(find.text('Nova Ordem de Fabricação'), findsWidgets);
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

  test('cards use a higher-contrast surface and an outline', () {
    for (final b in Brightness.values) {
      final t = appTheme(b);
      expect(t.cardTheme.color, t.colorScheme.surfaceContainerHigh);
      expect((t.cardTheme.shape as RoundedRectangleBorder).side.color, t.colorScheme.outlineVariant);
    }
  });
}

void backArrowTests() {
  testWidgets('screens inside a module go back to the module, others to the Painel', (tester) async {
    await pumpShell(tester, 'Admin');
    expect(find.byTooltip('Voltar para Painel'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('module-card-sales')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Voltar para Comercial'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Pedidos de venda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar para Comercial'));
    await tester.pumpAndSettle();
    expect(find.text('Telas de Comercial'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar ao Painel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Parâmetros'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar para Painel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('module-card-sales')), findsOneWidget);
  });
}

void painelExtrasTests() {
  testWidgets('Primeiros passos can be dismissed for good', (tester) async {
    await pumpShell(tester, 'Admin');
    expect(find.text('Primeiros passos'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tutorial-dismiss')));
    await tester.pumpAndSettle();
    expect(find.text('Primeiros passos'), findsNothing);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('tutorialDismissed'), isTrue);
    await pumpShell(tester, 'Admin', prefs: {'tutorialDismissed': true});
    expect(find.text('Primeiros passos'), findsNothing);
  });

  testWidgets('Painel quick actions follow the role and open the forms', (tester) async {
    await pumpShell(tester, 'Admin');
    for (final l in ['Novo pedido', 'Novo Orçamento', 'Nova Ordem de Fabricação', 'Nova requisição de compra']) {
      expect(find.widgetWithText(FilledButton, l), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Nova Ordem de Fabricação'));
    await tester.pumpAndSettle();
    expect(find.text('Nova ordem de fabricação'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await pumpShell(tester, 'Reader');
    expect(find.byKey(const ValueKey('quick-actions')), findsNothing);
  });
}
