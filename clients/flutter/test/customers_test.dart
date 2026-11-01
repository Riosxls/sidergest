import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/customers.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {'items': items, 'total': items.length, 'skip': 0, 'take': 50};

Map<String, dynamic> _customer({bool active = true, bool withCompany = true}) => {
  'id': 1, 'name': 'Metalúrgica Alfa', 'tradeName': 'Alfa', 'legacyCode': '12', 'consumerType': 'Normal', 'active': active,
  'company': withCompany
      ? {'document': '12345678000199', 'stateRegistration': '111', 'icmsContributor': true, 'street': 'Rua A', 'number': '10', 'city': 'Sorocaba', 'uf': 'SP', 'contact': 'Ana', 'email': 'a@alfa.com', 'phone': '1500', 'paymentTermName': '28 dias'}
      : null,
  'defaultAddress': null,
};

Map<String, dynamic> _address(int id) => {'id': id, 'city': 'Sorocaba', 'uf': 'SP', 'street': 'Rua B', 'number': '5', 'buyer': 'Beto', 'email': 'b@alfa.com', 'phone': '1511'};

class _Env {
  _Env({this.addresses = const [], this.withCompany = true});

  final List<Map<String, dynamic>> addresses;
  final bool withCompany;
  final log = <http.Request>[];

  http.Response answer(http.Request r) {
    log.add(r);
    final path = r.url.path;
    if (r.method == 'POST') return _json({..._customer(), 'id': 9});
    if (r.method == 'PUT' && path == '/api/customers/1') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      return _json({..._customer(withCompany: withCompany), ...body});
    }
    if (r.method == 'PUT') return _json({..._address(5), ...(jsonDecode(r.body) as Map<String, dynamic>)});
    if (r.method == 'DELETE') return http.Response('', 204);
    if (path == '/api/customers/1/addresses') return _json(addresses);
    if (path == '/api/customers/1') return _json(_customer(withCompany: withCompany));
    if (path == '/api/customers') return _json(_page([_customer(withCompany: withCompany)]));
    return _json(_page([]));
  }
}

Future<void> _pump(WidgetTester tester, _Env env, Widget Function(Session) screen, {String role = 'Admin'}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: MockClient((r) async => env.answer(r)), token: 'tok'))
    ..username = 'u'
    ..role = role
    ..permissions = rolePermissions[role]!;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: screen(session)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('fmtDocument formats CPF and CNPJ and leaves other values alone', () {
    expect(fmtDocument('12345678901'), '123.456.789-01');
    expect(fmtDocument('12345678000199'), '12.345.678/0001-99');
    expect(fmtDocument('abc'), 'abc');
    expect(fmtDocument(null), '');
  });

  testWidgets('customer list shows company columns and asks for active customers', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => CustomersScreen(session: s));
    expect(find.text('Metalúrgica Alfa'), findsOneWidget);
    expect(find.text('12.345.678/0001-99'), findsOneWidget);
    expect(find.text('Sorocaba/SP'), findsOneWidget);
    expect(env.log.first.url.queryParameters['active'], 'true');
  });

  testWidgets('new customer posts company data and a first delivery address', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => CustomersScreen(session: s));
    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-name')), 'Nova Ltda');
    await tester.enterText(find.byKey(const ValueKey('field-company.document')), '98765432000111');
    await tester.enterText(find.byKey(const ValueKey('field-company.uf')), 'SP');
    await tester.enterText(find.byKey(const ValueKey('field-company.contact')), 'Carla');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final post = env.log.firstWhere((r) => r.method == 'POST');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(post.url.path, '/api/customers');
    expect(body['name'], 'Nova Ltda');
    expect(body['company']['document'], '98765432000111');
    expect(body['address']['uf'], 'SP');
    expect(body['address']['buyer'], 'Carla');
  });

  testWidgets('customer screen shows company data, edits it and inactivates the customer', (tester) async {
    final env = _Env(addresses: [_address(5), _address(6)]);
    await _pump(tester, env, (s) => CustomerScreen(session: s, customer: _customer()));
    expect(find.text('Dados da empresa'), findsOneWidget);
    expect(find.text('12.345.678/0001-99'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar cadastro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-name')), 'Alfa Nova');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final put = env.log.firstWhere((r) => r.method == 'PUT');
    expect(jsonDecode(put.body)['name'], 'Alfa Nova');
    expect(find.textContaining('Alfa Nova'), findsWidgets);

    await tester.tap(find.byTooltip('Inativar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Inativar este cliente?'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(jsonDecode(env.log.where((r) => r.method == 'PUT').last.body)['active'], false);
    expect(find.textContaining('(inativo)'), findsOneWidget);
    expect(find.byTooltip('Reativar'), findsOneWidget);
  });

  testWidgets('customer without company data points to Editar', (tester) async {
    await _pump(tester, _Env(withCompany: false), (s) => CustomerScreen(session: s, customer: _customer(withCompany: false)));
    expect(find.textContaining('Sem dados cadastrados'), findsOneWidget);
  });

  testWidgets('delivery locais list marks the default and edits one', (tester) async {
    final env = _Env(addresses: [_address(5), _address(6)]);
    await _pump(tester, env, (s) => CustomerScreen(session: s, customer: _customer()));
    await tester.tap(find.text('Locais de entrega'));
    await tester.pumpAndSettle();
    expect(find.text('Sorocaba/SP  (padrão)'), findsOneWidget);
    expect(find.byTooltip('Local padrão'), findsOneWidget);
    await tester.tap(find.text('Sorocaba/SP  (padrão)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-buyer')), 'Dani');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final put = env.log.firstWhere((r) => r.method == 'PUT' && r.url.path == '/api/customers/1/addresses/5');
    expect(jsonDecode(put.body)['buyer'], 'Dani');
  });

  testWidgets('new delivery local copies the company fiscal data', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => CustomerScreen(session: s, customer: _customer()));
    await tester.tap(find.text('Locais de entrega'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum local de entrega'), findsOneWidget);
    await tester.tap(find.text('Novo local'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-uf')), 'SP');
    await tester.enterText(find.byKey(const ValueKey('field-city')), 'Votorantim');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final post = env.log.firstWhere((r) => r.method == 'POST' && r.url.path == '/api/customers/1/addresses');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['document'], '12345678000199');
    expect(body['city'], 'Votorantim');
  });

  testWidgets('new delivery local asks for company data first when there is none', (tester) async {
    final env = _Env(withCompany: false);
    await _pump(tester, env, (s) => CustomerScreen(session: s, customer: _customer(withCompany: false)));
    await tester.tap(find.text('Locais de entrega'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novo local'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cadastre os dados da empresa'), findsOneWidget);
  });

  testWidgets('quotes and orders tabs load the customer records', (tester) async {
    final env = _Env();
    await _pump(tester, env, (s) => CustomerScreen(session: s, customer: _customer()));
    await tester.tap(find.text('Orçamentos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pedidos'));
    await tester.pumpAndSettle();
    expect(env.log.any((r) => r.url.path == '/api/sales/quotes' && r.url.queryParameters['customerId'] == '1'), isTrue);
    expect(env.log.any((r) => r.url.path == '/api/sales/orders' && r.url.queryParameters['customerId'] == '1'), isTrue);
  });

  testWidgets('read-only role cannot create customers', (tester) async {
    await _pump(tester, _Env(), (s) => CustomersScreen(session: s), role: 'Reader');
    expect(find.text('Novo cliente'), findsNothing);
  });

  testWidgets('read-only role cannot inactivate or edit company data', (tester) async {
    await _pump(tester, _Env(addresses: [_address(5)]), (s) => CustomerScreen(session: s, customer: _customer()), role: 'Reader');
    expect(find.byTooltip('Inativar'), findsNothing);
    expect(find.text('Editar'), findsNothing);
  });
}
