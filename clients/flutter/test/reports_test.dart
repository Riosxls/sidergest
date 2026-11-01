import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/reports.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _money(num billed, {num kg = 10}) => {'billed': billed, 'icms': 1, 'ipi': 2, 'totalNoIpi': billed - 2, 'kg': kg, 'avgSalePrice': 5.5, 'avgMaterialCost': null};

Future<List<http.Request>> _pump(WidgetTester tester, Widget Function(Session) screen, http.Response Function(http.Request) answer) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    return answer(r);
  });
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
    ..username = 'adm'
    ..role = 'Admin'
    ..permissions = rolePermissions['Admin']!;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: screen(session)),
    ),
  );
  await tester.pumpAndSettle();
  return log;
}

void main() {
  testWidgets('material consumption groups rows by category, totals them and sorts on header tap', (tester) async {
    final log = await _pump(tester, (s) => MaterialConsumptionScreen(session: s), (r) {
      if (r.url.path == '/api/material-groups') {
        return _json({'items': [{'id': 1, 'code': 'BOB', 'name': 'Bobinas'}], 'total': 1});
      }
      return _json({
        'rows': [
          {'materialCode': 'B-2', 'materialDescription': 'Bobina dois', 'unit': 'KG', 'date': '2026-10-05', 'docNumber': 'OF 7', 'quantityKg': 12.5, 'invoiceNumber': 2590, 'note': 'ok', 'groupName': 'Bobinas'},
          {'materialCode': 'B-2', 'materialDescription': 'Bobina dois', 'unit': 'KG', 'date': '2026-10-02', 'docNumber': 'OF 6', 'quantityKg': 7.5, 'invoiceNumber': null, 'note': 'ok', 'groupName': 'Bobinas'},
          {'materialCode': 'X-1', 'materialDescription': 'Sem grupo', 'unit': 'KG', 'date': '2026-10-03', 'docNumber': 'OF 8', 'quantityKg': 1, 'invoiceNumber': null, 'note': 'ok'},
        ],
      });
    });
    expect(find.text('Categoria: Bobinas'), findsOneWidget);
    expect(find.text('Categoria: Sem categoria'), findsOneWidget);
    expect(find.text('Total retirado do material B-2'), findsOneWidget);
    expect(find.text('Total geral retirado do estoque'), findsOneWidget);
    expect(find.text('20,000'), findsOneWidget);
    expect(find.text('21,000'), findsOneWidget);
    for (final header in ['Data Movimento', 'Data Movimento', 'Código material', 'QTDE-KG Retirada']) {
      await tester.tap(find.text(header).last);
      await tester.pumpAndSettle();
    }
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'bobina');
    await tester.pumpAndSettle();
    expect(log.where((r) => r.url.path == '/api/reports/material-consumption').last.url.queryParameters['q'], 'bobina');
  });

  testWidgets('material consumption shows the friendly error when the API fails', (tester) async {
    await _pump(tester, (s) => MaterialConsumptionScreen(session: s), (r) => _json({'title': 'Falha no servidor'}, 500));
    expect(find.text('Nenhum registro no período'), findsOneWidget);
    expect(find.textContaining('Falha no servidor'), findsOneWidget);
  });

  testWidgets('billing summary lists companies, returns and net, filters by customer and sorts', (tester) async {
    await _pump(tester, (s) => BillingSummaryScreen(session: s), (r) {
      Map<String, dynamic> row(String c, num v) => {'customer': c, ..._money(v)};
      return _json({
        'companies': [
          {'key': 'EBT', 'rows': [row('Alfa', 100), row('Beta', 300)], 'total': _money(400)},
          {'key': 'BST', 'rows': [row('Gama', 50)], 'total': _money(50)},
        ],
        'grandTotal': _money(450),
        'returns': {'rows': [row('Alfa', 20)], 'total': _money(20)},
        'net': _money(430),
        'notes': ['Nota de rodapé'],
      });
    });
    expect(find.text('Empresa EBT'), findsOneWidget);
    expect(find.text('Empresa BST'), findsOneWidget);
    expect(find.text('Total faturado'), findsOneWidget);
    expect(find.text('Faturamento líquido'), findsOneWidget);
    expect(find.text('Nota de rodapé'), findsOneWidget);
    for (final header in ['Cliente', 'Cliente', 'Valor Fat.', 'ICMS', 'IPI', 'Total S/IPI', 'QTD.KG', 'PM.V R\$', 'PM.M R\$']) {
      await tester.tap(find.text(header).last);
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byType(TextField).last, 'gama');
    await tester.pumpAndSettle();
    expect(find.text('Gama'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
  });
}
