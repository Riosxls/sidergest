import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart' show appTheme;
import 'package:ebt_engenharia/screens/shell.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

final users = [
  {'id': 1, 'username': 'root', 'role': 'Admin', 'active': true, 'locked': false},
  {'id': 2, 'username': 'maria', 'role': 'Sales', 'active': true, 'locked': true},
];

Future<(Session, List<http.Request>)> pump(WidgetTester tester, String role) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    if (p == '/api/users' && r.method == 'GET') return json(users);
    if (p == '/api/users' && r.method == 'POST') return json({'id': 3, 'username': 'novo', 'role': 'Stock', 'active': true, 'locked': false}, 201);
    if (p == '/api/users/2/unlock') return http.Response('', 204);
    if (p == '/api/users/1' && r.method == 'PUT') return json({'title': 'At least one active Admin must remain', 'status': 409}, 409);
    if (p == '/api/access/matrix') {
      return json({
        'policies': ['read', 'admin', 'stock'],
        'roles': {
          'Reader': ['read'],
          'Admin': ['read', 'admin', 'stock'],
        },
      });
    }
    if (p == '/api/audit') {
      return json({
        'items': [
          {
            'id': 5,
            'at': '2026-01-02T10:30:00Z',
            'user': 'root',
            'entity': 'Customer',
            'entityId': '9',
            'action': 'Update',
            'changes': jsonEncode({
              'Name': {'from': 'Acme', 'to': 'Acme SA'},
            }),
          },
        ],
        'total': 1,
        'skip': 0,
        'take': 50,
      });
    }
    return json({'items': [], 'total': 0, 'skip': 0, 'take': 50});
  });
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
    ..username = 'ana'
    ..role = role
    ..permissions = rolePermissions[role]!;
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Shell(session: session),
    ),
  );
  await tester.pumpAndSettle();
  return (session, log);
}

Future<void> open(WidgetTester tester, String title) async {
  await tester.tap(find.widgetWithText(ListTile, title));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('non-admin roles do not see the admin screens', (tester) async {
    for (final role in rolePermissions.keys.where((r) => r != 'Admin')) {
      await pump(tester, role);
      for (final t in ['Usuários', 'Permissões', 'Auditoria']) {
        expect(find.widgetWithText(ListTile, t), findsNothing, reason: '$role/$t');
      }
      expect(find.widgetWithText(ListTile, 'Parâmetros'), findsOneWidget);
    }
  });

  testWidgets('Admin lists users, chips and unlock only for locked', (tester) async {
    final (_, log) = await pump(tester, 'Admin');
    await open(tester, 'Usuários');
    expect(log.any((r) => r.url.path == '/api/users'), isTrue);
    expect(find.text('root'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Vendas'), findsOneWidget);
    expect(find.text('Bloqueado'), findsOneWidget);
    expect(find.byKey(const ValueKey('unlock-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('unlock-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('unlock-2')));
    await tester.pumpAndSettle();
    expect(log.any((r) => r.method == 'POST' && r.url.path == '/api/users/2/unlock'), isTrue);
  });

  testWidgets('creating a user validates the password and posts the body', (tester) async {
    final (_, log) = await pump(tester, 'Admin');
    await open(tester, 'Usuários');
    await tester.tap(find.text('Novo usuário'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-username')), 'novo');
    await tester.enterText(find.byKey(const ValueKey('field-password')), 'curta');
    await tester.tap(find.byKey(const ValueKey('field-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estoque').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ao menos 10'), findsOneWidget);
    expect(log.where((r) => r.method == 'POST'), isEmpty);
    await tester.enterText(find.byKey(const ValueKey('field-password')), 'senha-longa-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    final post = log.singleWhere((r) => r.method == 'POST' && r.url.path == '/api/users');
    expect(jsonDecode(post.body), {'username': 'novo', 'password': 'senha-longa-123', 'role': 'Stock'});
  });

  testWidgets('editing warns about sign-out and shows the server message', (tester) async {
    final (_, log) = await pump(tester, 'Admin');
    await open(tester, 'Usuários');
    await tester.tap(find.byKey(const ValueKey('user-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('desconecta root'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    final put = log.singleWhere((r) => r.method == 'PUT');
    expect(jsonDecode(put.body), {'role': 'Admin', 'active': true});
    expect(find.text('At least one active Admin must remain'), findsOneWidget);
  });

  testWidgets('permission matrix shows a check for Admin/admin and none for Reader', (tester) async {
    await pump(tester, 'Admin');
    await open(tester, 'Permissões');
    expect(find.byKey(const ValueKey('cell-Admin-admin')), findsOneWidget);
    expect(find.byKey(const ValueKey('cell-Reader-admin')), findsNothing);
    expect(find.byKey(const ValueKey('cell-Reader-read')), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.textContaining('somente leitura'), findsOneWidget);
  });

  testWidgets('audit row opens a de/para detail and filters by entity', (tester) async {
    final (_, log) = await pump(tester, 'Admin');
    await open(tester, 'Auditoria');
    expect(find.text('Alterado'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    await tester.tap(find.text('root'));
    await tester.pumpAndSettle();
    expect(find.text('De'), findsOneWidget);
    expect(find.text('Para'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('Acme SA'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-Entidade')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Product').last);
    await tester.pumpAndSettle();
    expect(log.last.url.queryParameters['entity'], 'Product');
  });
}
