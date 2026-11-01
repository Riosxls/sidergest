import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart' show appTheme;
import 'package:ebt_engenharia/screens/fiscal.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> nf({String status = 'Authorized', bool simulated = false, String? message}) => {
  'id': 7,
  'number': 2581,
  'series': 1,
  'kind': 'Sale',
  'status': status,
  'simulated': simulated,
  'statusMessage': message,
  'cfopCode': '5101',
  'recipientName': 'Metalúrgica Alfa',
  'recipientDocument': '12.345.678/0001-90',
  'issuedAt': '2026-10-30T13:00:00Z',
  'invoiceTotal': 1250.5,
  'productsTotal': 1250.5,
  'freightTotal': 0,
  'icmsBase': 1250.5,
  'icmsTotal': 225.09,
  'ipiTotal': 0,
  'pisTotal': 0,
  'cofinsTotal': 0,
  'accessKey': '35261012345678000190550010000025811000000017',
  'protocol': '135260000000001',
  'environment': 'Homologation',
  'issuedBy': 'ana',
  'additionalInfo': null,
  'cancelReason': null,
  'cancelledBy': null,
  'cancelledAt': null,
  'lines': [
    {
      'sequence': 1,
      'code': 'TB-100',
      'description': 'Tubo redondo 25x1,5',
      'ncm': '73066100',
      'quantity': 10,
      'unit': 'PC',
      'unitPrice': 125.05,
      'total': 1250.5,
      'icmsCst': '00',
      'icmsValue': 225.09,
      'ipiCst': '53',
      'ipiValue': 0,
    },
  ],
  'installments': [
    {'sequence': 1, 'dueDate': '2026-11-30', 'amount': 1250.5},
  ],
};

Future<List<http.Request>> pump(WidgetTester tester, String role, Widget Function(Session) screen, Future<http.Response> Function(http.Request) handler) async {
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
      home: Scaffold(body: screen(session)),
    ),
  );
  await tester.pumpAndSettle();
  return log;
}

void main() {
  group('document list', () {
    Future<http.Response> list(http.Request r) async => json({
      'items': [
        {...nf(simulated: true), 'id': 7},
        {...nf(status: 'Rejected'), 'id': 8, 'number': 2582},
      ],
      'total': 2,
      'skip': 0,
      'take': 50,
    });

    testWidgets('shows number, status and the simulated flag', (tester) async {
      await pump(tester, 'SalesManager', (s) => FiscalDocumentsScreen(session: s), list);
      expect(find.text('2581'), findsOneWidget);
      expect(find.text('Autorizada'), findsOneWidget);
      expect(find.text('Rejeitada'), findsOneWidget);
      expect(find.text('Metalúrgica Alfa'), findsWidgets);
      expect(find.text('Sim'), findsOneWidget);
    });

    testWidgets('only a role that may cancel sees the inutilização button', (tester) async {
      await pump(tester, 'SalesManager', (s) => FiscalDocumentsScreen(session: s), list);
      expect(find.text('Inutilizar numeração'), findsOneWidget);
      await pump(tester, 'Sales', (s) => FiscalDocumentsScreen(session: s), list);
      expect(find.text('Inutilizar numeração'), findsNothing);
    });
  });

  group('document detail', () {
    Future<List<http.Request>> open(WidgetTester tester, String role, Map<String, dynamic> doc, [Future<http.Response?> Function(http.Request)? extra]) =>
        pump(tester, role, (s) => FiscalDocumentScreen(session: s, id: 7), (r) async {
          final e = extra == null ? null : await extra(r);
          if (e != null) return e;
          return json(doc);
        });

    testWidgets('an authorized NF shows items, totals, installments and the access key', (tester) async {
      await open(tester, 'SalesManager', nf());
      expect(find.textContaining('NF 2581'), findsWidgets);
      expect(find.text('Autorizada'), findsOneWidget);
      expect(find.text('Tubo redondo 25x1,5'), findsOneWidget);
      expect(find.text('Itens'), findsOneWidget);
      expect(find.text('Totais'), findsOneWidget);
      expect(find.text('Duplicatas'), findsOneWidget);
      expect(find.text('35261012345678000190550010000025811000000017'), findsOneWidget);
      expect(find.text('Homologação'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiscal-danfe')), findsOneWidget);
    });

    testWidgets('a simulated NF says it has no fiscal value', (tester) async {
      await open(tester, 'SalesManager', nf(simulated: true));
      expect(find.text('Autorização simulada'), findsOneWidget);
    });

    testWidgets('a pending NF offers reconciliation, not DANFE or cancel', (tester) async {
      await open(tester, 'SalesManager', nf(status: 'Pending'));
      expect(find.text('Aguardando resposta da SEFAZ'), findsOneWidget);
      expect(find.text('Conciliar com a SEFAZ'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiscal-danfe')), findsNothing);
      expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
    });

    testWidgets('reconcile posts to the document and reloads', (tester) async {
      final log = await open(tester, 'SalesManager', nf(status: 'Pending'), (r) async {
        if (r.method == 'POST' && r.url.path == '/api/fiscal/documents/7/reconcile') return json({'message': 'Autorizada na SEFAZ'});
        return null;
      });
      await tester.tap(find.text('Conciliar com a SEFAZ'));
      await tester.pumpAndSettle();
      final post = log.singleWhere((r) => r.method == 'POST');
      expect(post.url.queryParameters['minAgeMinutes'], '0');
      expect(find.text('Autorizada na SEFAZ'), findsOneWidget);
    });

    testWidgets('a rejected NF explains the lost number', (tester) async {
      await open(tester, 'SalesManager', nf(status: 'Rejected', message: 'Rejeição 539'));
      expect(find.text('NF rejeitada: número perdido'), findsOneWidget);
      expect(find.textContaining('Rejeição 539'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiscal-danfe')), findsNothing);
    });

    testWidgets('a cancelled NF shows who cancelled it and why', (tester) async {
      await open(tester, 'SalesManager', {...nf(status: 'Cancelled'), 'cancelReason': 'Pedido duplicado no sistema', 'cancelledBy': 'ana', 'cancelledAt': '2026-10-31T10:00:00Z'});
      expect(find.text('NF cancelada'), findsOneWidget);
      expect(find.textContaining('Pedido duplicado no sistema'), findsOneWidget);
      expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
    });

    testWidgets('a role without fiscal-cancel cannot cancel an authorized NF', (tester) async {
      await open(tester, 'Sales', nf());
      expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
    });

    testWidgets('cancelling asks for reason and password and posts both', (tester) async {
      final cancelled = {...nf(status: 'Cancelled'), 'cancelReason': 'Pedido duplicado no sistema'};
      final log = await open(tester, 'SalesManager', nf(), (r) async {
        if (r.method == 'POST' && r.url.path == '/api/fiscal/documents/7/cancel') return json(cancelled);
        return null;
      });
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar NF'));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'Pedido duplicado no sistema');
      await tester.enterText(fields.at(1), 'segredo-123');
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();
      final body = jsonDecode(log.singleWhere((r) => r.method == 'POST').body) as Map<String, dynamic>;
      expect(body['reason'], 'Pedido duplicado no sistema');
      expect(body['password'], 'segredo-123');
      expect(find.text('NF cancelada'), findsWidgets);
    });

    testWidgets('a load failure shows the friendly error', (tester) async {
      await pump(tester, 'SalesManager', (s) => FiscalDocumentScreen(session: s, id: 7), (r) async => json({'title': 'Registro bloqueado', 'status': 409}, 409));
      expect(find.textContaining('Registro bloqueado'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiscal-danfe')), findsNothing);
    });
  });

  group('settings', () {
    Map<String, dynamic> settings({bool enabled = false, String cnpj = ''}) => {
      'enabled': enabled,
      'environment': 'Homologation',
      'companyName': enabled ? 'EBT Indústria' : '',
      'cnpj': cnpj,
      'stateRegistration': '',
      'taxRegime': 3,
      'street': '',
      'city': '',
      'cityIbgeCode': '',
      'uf': 'SP',
      'series': 1,
      'nextNumber': 2581,
      'cancelWindowHours': 24,
    };

    testWidgets('off and incomplete: warns about the missing issuer data', (tester) async {
      await pump(tester, 'Admin', (s) => FiscalSettingsScreen(session: s), (r) async => json(settings()));
      expect(find.text('Emissão de NF-e desligada'), findsOneWidget);
      expect(find.text('Dados do emitente incompletos'), findsOneWidget);
      expect(find.textContaining('razão social, CNPJ, inscrição estadual, endereço completo'), findsOneWidget);
      expect(find.text('2581'), findsOneWidget);
      expect(find.text('24 h'), findsOneWidget);
    });

    testWidgets('on: says emission is live and the SEFAZ is still simulated', (tester) async {
      await pump(tester, 'Admin', (s) => FiscalSettingsScreen(session: s), (r) async => json(settings(enabled: true, cnpj: '12.345.678/0001-90')));
      expect(find.text('Emissão de NF-e ligada'), findsOneWidget);
      expect(find.textContaining('A SEFAZ ainda é simulada'), findsOneWidget);
    });

    testWidgets('only an admin can edit', (tester) async {
      await pump(tester, 'SalesManager', (s) => FiscalSettingsScreen(session: s), (r) async => json(settings()));
      expect(find.text('Editar parâmetros'), findsNothing);
      await pump(tester, 'Admin', (s) => FiscalSettingsScreen(session: s), (r) async => json(settings()));
      expect(find.text('Editar parâmetros'), findsOneWidget);
    });
  });
}
