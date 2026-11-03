import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart' show appTheme;
import 'package:ebt_engenharia/screens/receivables.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> row(int id, {String status = 'Open', num paid = 0, int days = 0}) => {
  'id': id,
  'documentId': 7,
  'number': 2581,
  'series': 1,
  'customerId': 3,
  'customerName': 'Metalúrgica Alfa',
  'sequence': id,
  'count': 2,
  'dueDate': '2026-12-01',
  'amount': 500,
  'paid': paid,
  'balance': 500 - paid,
  'status': status,
  'daysOverdue': days,
};

Future<List<http.Request>> pump(WidgetTester tester, String role, Future<http.Response> Function(http.Request) handler) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    return handler(r);
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
      home: Scaffold(body: ReceivablesScreen(session: session)),
    ),
  );
  await tester.pumpAndSettle();
  return log;
}

Future<http.Response> api(http.Request r) async {
  if (r.url.path == '/api/receivables/aging') {
    return json([
      {'customerId': 3, 'customerName': 'Metalúrgica Alfa', 'notDue': 300, 'days1To30': 200, 'days31To60': 0, 'days61To90': 0, 'over90': 0, 'total': 500},
      {'customerId': null, 'customerName': 'Total', 'notDue': 300, 'days1To30': 200, 'days31To60': 0, 'days61To90': 0, 'over90': 0, 'total': 500},
    ]);
  }
  if (r.url.path == '/api/receivables') {
    return json({
      'items': [row(1, status: 'Overdue', days: 12), row(2, status: 'Partial', paid: 100)],
      'total': 2,
      'skip': 0,
      'take': 50,
    });
  }
  if (r.url.path.endsWith('/payments') && r.method == 'GET') {
    return json([
      {'id': 9, 'installmentId': 2, 'paidOn': '2026-11-02', 'amount': 100, 'method': 'PIX', 'createdBy': 'ana', 'reversedAt': null},
    ]);
  }
  return json({'id': 9});
}

void main() {
  testWidgets('shows the aging card, the installments and their status', (tester) async {
    await pump(tester, 'SalesManager', api);
    expect(find.byKey(const ValueKey('receivables-aging')), findsOneWidget);
    expect(find.text('R\$ 200,00'), findsWidgets);
    expect(find.text('Vencida há 12 d'), findsOneWidget);
    expect(find.text('Pago em parte'), findsWidgets);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('the list asks for open installments by default and Só vencidas narrows it', (tester) async {
    final log = await pump(tester, 'SalesManager', api);
    expect(log.where((r) => r.url.path == '/api/receivables').first.url.queryParameters['status'], 'pending');
    await tester.tap(find.widgetWithText(FilterChip, 'Só vencidas'));
    await tester.pumpAndSettle();
    expect(log.where((r) => r.url.path == '/api/receivables').last.url.queryParameters['overdue'], 'true');
  });

  testWidgets('Dar baixa posts the payment with the balance as default amount', (tester) async {
    final log = await pump(tester, 'SalesManager', api);
    await tester.ensureVisible(find.byTooltip('Ações').first);
    await tester.tap(find.byTooltip('Ações').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dar baixa'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    final post = log.firstWhere((r) => r.method == 'POST');
    expect(post.url.path, '/api/receivables/installments/1/payments');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['amount'], 500);
    expect(body['paidOn'], isNotNull);
  });

  testWidgets('Estornar lists the payments and sends the reason', (tester) async {
    final log = await pump(tester, 'Admin', api);
    await tester.ensureVisible(find.byTooltip('Ações').last);
    await tester.tap(find.byTooltip('Ações').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estornar'));
    await tester.pumpAndSettle();
    expect(find.text('PIX', findRichText: true), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Estornar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Pagamento duplicado');
    await tester.tap(find.widgetWithText(FilledButton, 'Estornar'));
    await tester.pumpAndSettle();
    final del = log.firstWhere((r) => r.method == 'DELETE');
    expect(del.url.path, '/api/receivables/payments/9');
    expect(del.url.queryParameters['reason'], 'Pagamento duplicado');
  });

  testWidgets('a role without receivables-post sees no baixa or estorno', (tester) async {
    await pump(tester, 'Reader', api);
    expect(find.byTooltip('Ações'), findsNothing);
    expect(find.text('Dar baixa'), findsNothing);
  });
}
