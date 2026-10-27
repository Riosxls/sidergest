import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/main.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> page(List<Map<String, dynamic>> items) => {'items': items, 'total': items.length, 'skip': 0, 'take': 50};

final product = {
  'id': 1,
  'code': 'T-100',
  'name': 'Tubo 25x1,5',
  'kind': 'Part',
  'shape': 'Circular',
  'diameterMm': 25,
  'widthMm': null,
  'heightMm': null,
  'thicknessMm': 1.5,
  'lengthMm': 6000,
  'netWeightKg': 5.27,
  'lossPercent': null,
  'ncm': '73063000',
  'stockUnit': 'PC',
  'piecesPerPackage': null,
  'blocked': false,
  'drawingRevision': null,
  'processRevision': null,
  'operationCount': 1,
};

MockClient fakeBackend(List<http.Request> log) => MockClient((r) async {
  log.add(r);
  final path = r.url.path;
  if (path == '/api/auth/login') {
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    if (b['password'] != 'senha-correta') return http.Response('', 401);
    return json({
      'token': 'tok',
      'expiresAt': DateTime.now().add(const Duration(hours: 8)).toUtc().toIso8601String(),
      'username': 'eng',
      'role': 'Engineering',
    });
  }
  if (r.headers['Authorization'] != 'Bearer tok') return http.Response('', 401);
  if (path == '/api/products' && r.method == 'GET') return json(page([product]));
  if (path == '/api/products' && r.method == 'POST') {
    return json({
      'type': 'https://tools.ietf.org/html/rfc9110#section-15.5.1',
      'title': 'One or more validation errors occurred.',
      'status': 400,
      'errors': {
        'ncm': ['NCM must have 8 digits'],
      },
    }, 400);
  }
  if (path == '/api/products/1') return json(product);
  if (path == '/api/products/1/routing') {
    return json([
      {
        'id': 7,
        'productId': 1,
        'sequence': 10,
        'standardOperationId': 3,
        'machineId': null,
        'machineCode': 'SERRA1',
        'workCenterId': null,
        'toolId': null,
        'setupHours': 0.5,
        'piecesPerHour': 120,
        'operators': 1,
        'description': null,
        'standard': null,
        'notes': null,
        'items': [
          {'id': 9, 'materialId': 4, 'componentProductId': null, 'code': 'BOB-15', 'description': 'Bobina 1,5mm', 'quantity': 5.4, 'unit': 'KG', 'factor': 1},
        ],
      },
    ]);
  }
  if (path == '/api/standard-operations') {
    return json(
      page([
        {'id': 3, 'code': 'COR', 'name': 'Corte'},
      ]),
    );
  }
  if (path == '/api/products/1/bom/explode') {
    final q = num.parse(r.url.queryParameters['quantity']!);
    return json({
      'productId': 1,
      'productCode': 'T-100',
      'quantity': q,
      'lines': [
        {
          'level': 1,
          'productId': 1,
          'productCode': 'T-100',
          'operationSequence': 10,
          'materialId': 4,
          'componentProductId': null,
          'code': 'BOB-15',
          'description': 'Bobina 1,5mm',
          'unit': 'KG',
          'quantityPerUnit': 5.4,
          'totalQuantity': 5.4 * q,
        },
      ],
      'materials': [
        {'materialId': 4, 'code': 'BOB-15', 'description': 'Bobina 1,5mm', 'unit': 'KG', 'totalQuantity': 5.4 * q},
      ],
    });
  }
  if (path.endsWith('/where-used') || path.endsWith('/revisions')) return json([]);
  return http.Response('', 404);
});

Future<Session> pumpApp(WidgetTester tester, List<http.Request> log) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session(
    api: ApiClient(baseUrl: 'http://api.test', client: fakeBackend(log)),
  );
  await session.restore();
  session.api.baseUrl = 'http://api.test';
  await tester.pumpWidget(EbtApp(session: session));
  return session;
}

Future<void> login(WidgetTester tester, String password) async {
  await tester.enterText(find.byKey(const ValueKey('login-user')), 'eng');
  await tester.enterText(find.byKey(const ValueKey('login-password')), password);
  await tester.tap(find.text('Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  test('fmt and parseDecimal handle Brazilian notation', () {
    expect(fmt(1.5), '1,5');
    expect(fmt(6000), '6000');
    expect(fmt(true), 'Sim');
    expect(parseDecimal('1,5'), 1.5);
    expect(parseDecimal('1.234,5'), 1234.5);
    expect(parseDecimal('1.5'), 1.5);
    expect(parseDecimal('x'), isNull);
  });

  test('ApiClient maps validation problems to field errors', () async {
    final api = ApiClient(baseUrl: 'http://api.test', token: 'tok', client: fakeBackend([]));
    await expectLater(
      api.post('/api/products', {}),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 400).having((e) => e.fieldErrors['ncm'], 'ncm', ['NCM must have 8 digits'])),
    );
  });

  testWidgets('wrong password shows error, right password opens the shell', (tester) async {
    final log = <http.Request>[];
    final session = await pumpApp(tester, log);
    await login(tester, 'errada');
    expect(find.textContaining('inválidos'), findsOneWidget);
    expect(session.loggedIn, isFalse);

    await login(tester, 'senha-correta');
    expect(session.loggedIn, isTrue);
    expect(session.canWrite, isTrue);
    await tester.tap(find.byTooltip('Conta'));
    await tester.pumpAndSettle();
    expect(find.text('eng'), findsOneWidget);
    expect(find.text('Engineering'), findsOneWidget);
  });

  testWidgets('product list, server validation errors and product detail with explosion', (tester) async {
    final log = <http.Request>[];
    await pumpApp(tester, log);
    await login(tester, 'senha-correta');

    await tester.tap(find.byKey(const ValueKey('module-card-engineering')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Produtos').first);
    await tester.pumpAndSettle();
    expect(find.text('T-100'), findsOneWidget);

    await tester.tap(find.text('Novo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Obrigatório'), findsNWidgets(3));

    await tester.enterText(find.byKey(const ValueKey('field-code')), 'X');
    await tester.enterText(find.byKey(const ValueKey('field-name')), 'Teste');
    await tester.enterText(find.byKey(const ValueKey('field-ncm')), '123');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('NCM must have 8 digits'), findsOneWidget);
    final post = log.lastWhere((r) => r.method == 'POST');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['kind'], 'Part');
    expect(body['stockUnit'], 'PC');
    expect(body['blocked'], false);
    expect(body['diameterMm'], isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('T-100'));
    await tester.pumpAndSettle();
    expect(find.text('Corte'), findsOneWidget);
    expect(find.textContaining('BOB-15'), findsOneWidget);
    expect(find.text('Máquina SERRA1 · Setup 0,5 h · 120 pç/h · 1 oper.'), findsOneWidget);

    await tester.tap(find.text('Explosão'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('explode-qty')), '10');
    await tester.tap(find.text('Explodir'));
    await tester.pumpAndSettle();
    expect(log.last.url.queryParameters['quantity'], '10');
    expect(find.text('54 KG'), findsNWidgets(2));
  });

  testWidgets('narrow layout uses a drawer and list tiles', (tester) async {
    final log = <http.Request>[];
    await pumpApp(tester, log);
    tester.view.physicalSize = const Size(400, 800);
    await login(tester, 'senha-correta');
    await tester.tap(find.byKey(const ValueKey('module-card-engineering')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Produtos').last);
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsNothing);
    expect(find.widgetWithText(ListTile, 'T-100  Tubo 25x1,5'), findsOneWidget);
  });
}
