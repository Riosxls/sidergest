import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/dashboard.dart' show modules;
import 'package:ebt_engenharia/screens/modules.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

Future<void> _open(WidgetTester tester, String module, String role, {List<String>? opened}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session(
    api: ApiClient(baseUrl: 'http://api.test', token: 'tok', client: MockClient((r) async => http.Response('{"items":[],"total":0}', 200, headers: {'content-type': 'application/json'}))),
  )..permissions = rolePermissions[role]!;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ModuleScreen(session: session, module: modules.firstWhere((m) => m.section == module), links: const [], onNavigate: (id, [f]) => opened?.add(id)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _all = {
  'Comercial': ['Novo orçamento', 'Novo pedido de venda', 'Nova análise de viabilidade', 'Simulador de preço'],
  'Engenharia': ['Novo produto', 'Nova matéria-prima'],
  'PCP': ['Nova ordem de fabricação', 'Novo apontamento'],
  'Suprimentos': ['Nova requisição', 'Novo pedido de compra', 'Estoque mínimo'],
  'Estoque': ['Novo lançamento', 'Nova reserva', 'Estoque mínimo'],
};

void main() {
  for (final e in _all.entries) {
    testWidgets('${e.key} shows its own quick actions and nothing from other sectors', (tester) async {
      await _open(tester, e.key, 'Admin');
      for (final label in e.value) {
        expect(find.widgetWithText(FilledButton, label), findsOneWidget, reason: label);
      }
      for (final other in _all.entries.where((o) => o.key != e.key).expand((o) => o.value).where((l) => !e.value.contains(l))) {
        expect(find.widgetWithText(FilledButton, other), findsNothing, reason: '$other in ${e.key}');
      }
    });

    testWidgets('${e.key} shows no create shortcuts to a reader', (tester) async {
      await _open(tester, e.key, 'Reader');
      for (final label in e.value.where((l) => l != 'Estoque mínimo')) {
        expect(find.widgetWithText(FilledButton, label), findsNothing, reason: label);
      }
    });
  }

  testWidgets('the low-stock shortcut opens that screen of the shell', (tester) async {
    final opened = <String>[];
    await _open(tester, 'Estoque', 'Admin', opened: opened);
    await tester.tap(find.widgetWithText(FilledButton, 'Estoque mínimo'));
    await tester.pumpAndSettle();
    expect(opened, ['low-stock']);
  });

  testWidgets('the stock role gets stock shortcuts but not sales ones', (tester) async {
    await _open(tester, 'Estoque', 'Stock');
    expect(find.widgetWithText(FilledButton, 'Novo lançamento'), findsOneWidget);
    await _open(tester, 'Comercial', 'Stock');
    expect(find.widgetWithText(FilledButton, 'Novo orçamento'), findsNothing);
  });
}
