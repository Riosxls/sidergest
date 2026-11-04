import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/quick_actions.dart';
import 'package:ebt_engenharia/screens/quick_actions_editor.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

Session _session(String role) => Session(
  api: ApiClient(baseUrl: 'http://api.test', token: 'tok', client: MockClient((r) async => http.Response('{}', 200, headers: {'content-type': 'application/json'}))),
)..permissions = rolePermissions[role]!;

Future<void> _pump(WidgetTester tester, Session s) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ListenableBuilder(
        listenable: s,
        builder: (context, _) => Scaffold(
          body: Builder(
            builder: (context) => QuickActionBar(actions: quickActionsFor(s, go: (_) {}), onEdit: () => showQuickActionsEditor(context, s)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('without a choice the Painel shows the five default shortcuts', (tester) async {
    final s = _session('Admin');
    expect([for (final a in quickActionsFor(s)) a.label], ['Novo orçamento', 'Novo produto', 'Nova ordem de fabricação', 'Nova requisição', 'Novo pedido ao fornecedor']);
    await _pump(tester, s);
    expect(find.byKey(const ValueKey('quick-actions-edit')), findsOneWidget);
  });

  testWidgets('swapping Novo pedido for Estoque mínimo is saved and shown', (tester) async {
    final s = _session('Admin');
    await _pump(tester, s);
    await tester.tap(find.byKey(const ValueKey('quick-actions-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-actions-count')), findsOneWidget);
    // full: nothing can be added until one is removed
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('add-low-stock'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('remove-new-purchase-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-low-stock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-actions-save')));
    await tester.pumpAndSettle();
    expect(s.quickActionIds, ['new-quote', 'new-product', 'new-production-order', 'new-requisition', 'low-stock']);
    expect(find.widgetWithText(FilledButton, 'Estoque mínimo'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Novo pedido ao fornecedor'), findsNothing);
    expect((await SharedPreferences.getInstance()).getStringList('quickActions'), s.quickActionIds);
  });

  testWidgets('the limit is five: adding is disabled while five are in use', (tester) async {
    final s = _session('Admin')..quickActionIds = ['new-quote', 'new-product', 'new-material', 'new-report', 'new-reservation'];
    await _pump(tester, s);
    await tester.tap(find.byKey(const ValueKey('quick-actions-edit')));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('add-new-sales-order'))).onPressed, isNull);
    expect(find.textContaining('Limite de 5 atalhos'), findsWidgets);
  });

  testWidgets('Restaurar padrão and saving the default set clears the stored choice', (tester) async {
    final s = _session('Admin')..quickActionIds = ['low-stock'];
    await _pump(tester, s);
    await tester.tap(find.byKey(const ValueKey('quick-actions-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-actions-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-actions-save')));
    await tester.pumpAndSettle();
    expect(s.quickActionIds, isNull);
    expect((await SharedPreferences.getInstance()).getStringList('quickActions'), isNull);
  });

  testWidgets('picks the role cannot use are skipped, and an all-invalid pick falls back to the defaults', (tester) async {
    final s = _session('Reader')..quickActionIds = ['new-quote', 'new-product'];
    expect(quickActionsFor(s), isEmpty);
    final admin = _session('Admin')..quickActionIds = ['nonexistent'];
    expect(quickActionsFor(admin), hasLength(5));
    final stock = _session('Stock')..quickActionIds = ['new-reservation', 'new-quote'];
    expect([for (final a in quickActionsFor(stock)) a.id], ['new-reservation']);
  });

  testWidgets('the stored choice survives a restart and is capped at five', (tester) async {
    SharedPreferences.setMockInitialValues({
      'quickActions': ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
    });
    final s = Session();
    await s.restore();
    expect(s.quickActionIds, ['a', 'b', 'c', 'd', 'e']);
  });
}
