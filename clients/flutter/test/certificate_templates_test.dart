import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/certificates.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _certificate() => {
  'id': 7,
  'reference': '5176-26',
  'orderId': 3,
  'orderReference': 'PV 3',
  'deliveryId': null,
  'issueDate': '2026-10-30',
  'quantity': 413,
  'unit': 'KG',
  'description': 'Tubo 06,35 X 0,70 X 6000',
  'finish': 'Isento de porosidade / Manchas / Riscos e Corrosão',
  'title': null,
  'notes': null,
  'status': 'Draft',
  'measures': [
    {'kind': 'Chemical', 'name': 'C', 'sequence': 1, 'specified': 'Máx. 0,150', 'found': null},
    {'kind': 'Chemical', 'name': 'Mn', 'sequence': 2, 'specified': 'Máx. 0,700', 'found': null},
    {'kind': 'Mechanical', 'name': 'LR', 'sequence': 1, 'specified': '290 Mpa mín.', 'found': null},
  ],
};

Future<(List<http.Request>, Session)> _pump(WidgetTester tester, Widget Function(Session s) screen, {Object? templates}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    if (p == '/api/sales/orders/3') return _json({'deliveries': []});
    if (p == '/api/sales/certificates/7' && r.method == 'PUT') return _json(_certificate());
    if (p == '/api/sales/certificates/templates' && r.method == 'GET') return _json(templates ?? []);
    if (p.startsWith('/api/sales/certificates/templates/') && r.method == 'DELETE') return http.Response('', 204);
    return _json({'items': [], 'total': 0, 'skip': 0, 'take': 50});
  });
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
    ..username = 'ana'
    ..role = 'Sales'
    ..permissions = rolePermissions['Sales']!;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: screen(session),
    ),
  );
  await tester.pumpAndSettle();
  return (log, session);
}

void main() {
  testWidgets('editor adds and removes rows, sets the title and inserts note snippets', (tester) async {
    final (log, _) = await _pump(tester, (s) => CertificateEditorScreen(session: s, certificate: _certificate()));
    expect(find.textContaining('As especificações vêm do último certificado emitido'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('row-del-Chemical-Mn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('found-Chemical-Mn')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('row-add-Mechanical')));
    await tester.tap(find.byKey(const ValueKey('row-add-Mechanical')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Teste destrutivo');
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('found-Mechanical-Teste destrutivo')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('found-Mechanical-Teste destrutivo')), 'ok');

    await tester.ensureVisible(find.byKey(const ValueKey('cert-title')));
    await tester.tap(find.byKey(const ValueKey('cert-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CERTIFICADO DE GARANTIA DA QUALIDADE DO PRODUTO').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('note-snippet-1')));
    await tester.tap(find.byKey(const ValueKey('note-snippet-1')));
    await tester.tap(find.byKey(const ValueKey('note-snippet-0')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('cert-notes'))).controller!.text, 'MATERIAL RECOZIDO\nCertificado de origem do material nº ');

    await tester.tap(find.byKey(const ValueKey('cert-save')));
    await tester.pumpAndSettle();
    final body = jsonDecode(log.lastWhere((r) => r.method == 'PUT').body) as Map<String, dynamic>;
    expect(body['title'], 'CERTIFICADO DE GARANTIA DA QUALIDADE DO PRODUTO');
    expect(body['notes'], 'MATERIAL RECOZIDO\nCertificado de origem do material nº');
    final names = (body['measures'] as List).map((m) => m['name']).toList();
    expect(names, ['C', 'LR', 'Teste destrutivo']);
    expect((body['measures'] as List).last['found'], 'ok');
    expect((body['measures'] as List).first['specified'], 'Máx. 0,150');
  });

  testWidgets('template list shows what was learned and can forget it', (tester) async {
    final templates = [
      {
        'id': 4,
        'productId': 1,
        'productCode': '060.350.60',
        'productDescription': 'Tubo 06,35 X 0,70 X 6000',
        'customerId': 2,
        'customerName': 'Incodiesel',
        'title': 'CERTIFICADO DE GARANTIA DA QUALIDADE DO PRODUTO',
        'finish': null,
        'notes': 'MATERIAL RECOZIDO',
        'learnedFrom': '5175-26',
        'measures': [
          {'kind': 'Chemical', 'name': 'C', 'sequence': 1, 'specified': 'Máx. 0,150', 'found': null},
        ],
      },
    ];
    final (log, _) = await _pump(tester, (s) => CertificateTemplatesScreen(session: s), templates: templates);
    expect(find.text('Incodiesel · 060.350.60'), findsOneWidget);
    expect(find.textContaining('aprendido do certificado 5175-26'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('templates-search')), 'xyz');
    await tester.pump();
    expect(find.text('Nada encontrado.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('templates-search')), 'incod');
    await tester.pump();
    await tester.tap(find.text('Incodiesel · 060.350.60'));
    await tester.pumpAndSettle();
    expect(find.text('Química · C: Máx. 0,150'), findsOneWidget);
    expect(find.text('Observações: MATERIAL RECOZIDO'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('template-forget-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-step')));
    await tester.pumpAndSettle();
    expect(log.any((r) => r.method == 'DELETE' && r.url.path == '/api/sales/certificates/templates/4'), isTrue);
  });

  testWidgets('empty template list explains how it fills', (tester) async {
    await _pump(tester, (s) => CertificateTemplatesScreen(session: s));
    expect(find.textContaining('Nenhum modelo ainda'), findsOneWidget);
  });
}
