import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/screens/login.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/entity_form.dart';
import 'package:ebt_engenharia/widgets/record_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Filtered extends StatefulWidget {
  const _Filtered({required this.api});

  final ApiClient api;

  @override
  State<_Filtered> createState() => _FilteredState();
}

class _FilteredState extends State<_Filtered> {
  bool _open = true;

  @override
  Widget build(BuildContext context) => RecordList(
    api: widget.api,
    path: '/api/things',
    query: {'open': _open ? true : null},
    filters: [FilterChip(label: const Text('Somente abertos'), selected: _open, onSelected: (v) => setState(() => _open = v))],
    filtersActive: _open,
    onClearFilters: () => setState(() => _open = false),
    emptyText: 'Nada cadastrado',
    columns: [col('Nome', 'name'), col('Total', 'total', numeric: true), col('Dia', 'day')],
  );
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('friendlyError', () {
    test('keeps API messages and names the field in Portuguese', () {
      expect(friendlyError(ApiException(404, 'Registro não encontrado')), 'Registro não encontrado');
      final e = ApiException(400, 'x', {
        'customerId': ['Obrigatório'],
        'Lines[1].unitPrice': ['Inválido'],
        'someOtherField': ['Ruim'],
      });
      expect(friendlyError(e), 'Cliente: Obrigatório\nLinha 2 · Preço unitário: Inválido\nSome other field: Ruim');
    });

    test('never leaks raw exception text', () {
      expect(friendlyError(Exception('SocketException: connection refused 10.0.0.1')), 'Não foi possível concluir. Tente novamente.');
      expect(friendlyError(const FormatException('Unexpected character')), contains('Resposta inesperada'));
    });
  });

  testWidgets('empty list with a filter on explains it and clears the filter', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((r) async {
      final open = r.url.queryParameters['open'] == 'true';
      final items = open
          ? <Map<String, dynamic>>[]
          : [
              {'name': 'B', 'total': 200, 'day': '2026-02-01'},
              {'name': 'A', 'total': 1000, 'day': '2026-01-05'},
            ];
      return http.Response(jsonEncode({'items': items, 'total': items.length, 'skip': 0, 'take': 50}), 200);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Filtered(api: ApiClient(baseUrl: 'http://x', client: client)))));
    await tester.pumpAndSettle();

    expect(find.text('Nada encontrado com a busca e os filtros atuais'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clear-filters')));
    await tester.pumpAndSettle();

    expect(find.text('Nada encontrado com a busca e os filtros atuais'), findsNothing);
    expect(find.text('A'), findsOneWidget);
    // Unfiltered and empty would say the plain empty text instead.
    expect(find.text('Nada cadastrado'), findsNothing);
  });

  testWidgets('clicking a column header sorts the page, numbers by value', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((r) async {
      final items = [
        {'name': 'B', 'total': 200, 'day': '2026-02-01'},
        {'name': 'A', 'total': 1000, 'day': '2026-01-05'},
      ];
      return http.Response(jsonEncode({'items': items, 'total': 2, 'skip': 0, 'take': 50}), 200);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Filtered(api: ApiClient(baseUrl: 'http://x', client: client)))));
    await tester.pumpAndSettle();
    // Unsorted: server order.
    expect(tester.getTopLeft(find.text('B')).dy, lessThan(tester.getTopLeft(find.text('A')).dy));

    await tester.tap(find.text('Nome'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('A')).dy, lessThan(tester.getTopLeft(find.text('B')).dy));

    await tester.tap(find.text('Nome'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('B')).dy, lessThan(tester.getTopLeft(find.text('A')).dy));
  });

  testWidgets('a failed load shows a retry button', (tester) async {
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      if (calls == 1) return http.Response('boom', 500);
      return http.Response(jsonEncode({'items': <Object>[], 'total': 0, 'skip': 0, 'take': 50}), 200);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Filtered(api: ApiClient(baseUrl: 'http://x', client: client)))));
    await tester.pumpAndSettle();
    expect(find.text('Tentar novamente'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Tentar novamente'), findsNothing);
    expect(calls, 2);
  });

  testWidgets('login can reveal the password', (tester) async {
    final session = Session();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(session: session)));
    await tester.enterText(find.byKey(const ValueKey('login-password')), 'segredo');
    EditableText field() => tester.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey('login-password')), matching: find.byType(EditableText)));
    expect(field().obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey('login-toggle-password')));
    await tester.pump();
    expect(field().obscureText, isFalse);
  });

  group('remember login', () {
    http.Response loginOk() => http.Response(
      jsonEncode({
        'token': 't1',
        'username': 'ana',
        'role': 'Reader',
        'permissions': ['read'],
        'expiresAt': DateTime.now().add(const Duration(minutes: 60)).toUtc().toIso8601String(),
        'refreshToken': 'r1',
        'refreshExpiresAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
      }),
      200,
    );

    Session newSession() => Session(api: ApiClient(baseUrl: 'http://x', client: MockClient((_) async => loginOk())));

    test('remembered: tokens are stored and the username is offered next time', () async {
      final s = newSession();
      await s.login('http://x', 'ana', 'pw');
      expect((await const FlutterSecureStorage().readAll())['token'], 't1');
      final again = newSession();
      await again.restore();
      expect(again.lastUser, 'ana');
      expect(again.remember, isTrue);
      expect(again.loggedIn, isTrue);
    });

    test('not remembered: nothing is stored and the username is forgotten', () async {
      final s = newSession();
      await s.login('http://x', 'ana', 'pw', remember: false);
      expect(s.loggedIn, isTrue);
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
      final again = newSession();
      await again.restore();
      expect(again.loggedIn, isFalse);
      expect(again.lastUser, '');
      expect(again.remember, isFalse);
    });

    test('setRemember(false) removes the stored session and setRemember(true) stores it again', () async {
      final s = newSession();
      await s.login('http://x', 'ana', 'pw');
      await s.setRemember(false);
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
      expect(s.loggedIn, isTrue, reason: 'the running session is untouched');
      await s.setRemember(true);
      expect((await const FlutterSecureStorage().readAll())['token'], 't1');
      final again = newSession();
      await again.restore();
      expect(again.lastUser, 'ana');
      expect(again.loggedIn, isTrue);
    });

    testWidgets('screen: checkbox defaults on, can be cleared, and the saved user is prefilled', (tester) async {
      SharedPreferences.setMockInitialValues({'lastUser': 'ana'});
      final s = newSession();
      await s.restore();
      await tester.pumpWidget(MaterialApp(home: LoginScreen(session: s)));
      expect(tester.widget<TextField>(find.byKey(const ValueKey('login-user'))).controller!.text, 'ana');
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('login-remember'))).value, isTrue);
      await tester.tap(find.byKey(const ValueKey('login-remember')));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('login-remember'))).value, isFalse);
      expect(find.text('A sessão termina ao fechar o aplicativo'), findsOneWidget);
    });

    testWidgets('wrong password shows a short message and keeps the username', (tester) async {
      final s = Session(api: ApiClient(baseUrl: 'http://x', client: MockClient((_) async => http.Response('', 401))));
      await tester.pumpWidget(MaterialApp(home: LoginScreen(session: s)));
      await tester.enterText(find.byKey(const ValueKey('login-user')), 'ana');
      await tester.enterText(find.byKey(const ValueKey('login-password')), 'errada');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('Usuário ou senha inválidos'), findsOneWidget);
      expect(find.textContaining('sessão expirada'), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('login-user'))).controller!.text, 'ana');
    });

    testWidgets('server down reveals the server address field', (tester) async {
      final s = Session(api: ApiClient(baseUrl: 'http://x', client: MockClient((_) async => throw Exception('offline'))));
      await tester.pumpWidget(MaterialApp(home: LoginScreen(session: s)));
      await tester.enterText(find.byKey(const ValueKey('login-user')), 'ana');
      await tester.enterText(find.byKey(const ValueKey('login-password')), 'pw');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-url')), findsOneWidget);
      expect(find.textContaining('Servidor indisponível'), findsOneWidget);
    });
  });

  group('form dialogs', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = ApiClient(baseUrl: 'http://x', client: MockClient((_) async => http.Response('{}', 200)));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => showEntityForm(
                  c,
                  api: api,
                  title: 'Formulário de teste',
                  fields: [
                    const FieldSpec('note', 'Detalhes', hint: 'Um texto de ajuda bem longo que precisa quebrar em várias linhas em vez de terminar em reticências no meio da frase, porque cortar a explicação deixa o usuário sem saber o que acontece.'),
                  ],
                  onSubmit: (_) async => null,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('long helper text wraps instead of being cut with an ellipsis', (tester) async {
      await open(tester);
      final decorator = tester.widget<InputDecorator>(find.descendant(of: find.byKey(const ValueKey('field-note')), matching: find.byType(InputDecorator)));
      expect(decorator.decoration.helperMaxLines, greaterThan(1));
    });

    testWidgets('clicking the backdrop or pressing Esc closes an untouched dialog', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Formulário de teste'), findsNothing);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Formulário de teste'), findsNothing);
    });

    testWidgets('with edits typed, backdrop and Esc ask before discarding', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('field-note')), 'texto digitado');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.text('Formulário de teste'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(find.text('Formulário de teste'), findsNothing);
    });
  });
}
