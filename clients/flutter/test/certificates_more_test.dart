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

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {'items': items, 'total': items.length, 'skip': 0, 'take': 50};

Map<String, dynamic> _cert({String status = 'Draft', bool found = false, int? deliveryId, String? cancelReason}) => {
  'id': 7,
  'reference': '5176-26',
  'company': 'BST',
  'orderId': 3,
  'orderReference': 'PV 3',
  'customerName': 'Incodiesel',
  'customerPo': 'PC-99',
  'effectiveInvoiceNumber': deliveryId == null ? null : '4321',
  'deliveryId': deliveryId,
  'deliveryReference': deliveryId == null ? null : 'ENT 2',
  'issueDate': '2026-10-30',
  'quantity': 413,
  'unit': 'KG',
  'productCode': '060.350.60',
  'description': 'Tubo 06,35 X 0,70 X 6000',
  'finish': 'Isento de porosidade',
  'title': null,
  'notes': null,
  'status': status,
  'cancelReason': cancelReason,
  'createdBy': 'ana',
  'createdAt': '2026-10-30T10:00:00Z',
  'measures': [
    {'kind': 'Chemical', 'name': 'C', 'sequence': 1, 'specified': 'Máx. 0,150', 'found': found ? '0,08' : null},
    {'kind': 'Dimensional', 'name': 'Espessura', 'sequence': 1, 'specified': '0,65 a 0,75', 'found': found ? '0,70' : null},
    {'kind': 'Mechanical', 'name': 'LR', 'sequence': 1, 'specified': '290 Mpa mín.', 'found': found ? '310' : null},
  ],
};

Map<String, dynamic> _template({int id = 4}) => {
  'id': id,
  'productId': 1,
  'productCode': '060.350.60',
  'productDescription': 'Tubo 06,35 X 0,70 X 6000',
  'customerId': 2,
  'customerName': 'Incodiesel',
  'title': null,
  'finish': 'Liso',
  'notes': null,
  'learnedFrom': '5175-26',
  'measures': [
    {'kind': 'Chemical', 'name': 'C', 'sequence': 1, 'specified': 'Máx. 0,150', 'found': null},
    {'kind': 'Mechanical', 'name': 'LR', 'sequence': 1, 'specified': null, 'found': null},
  ],
};

class _Fake {
  final log = <http.Request>[];
  var role = 'Admin';
  Map<String, dynamic> cert = _cert();
  List<Map<String, dynamic>> certs = [_cert()];
  List<Map<String, dynamic>> deliveries = [];
  List<Map<String, dynamic>> templates = [];
  int certStatus = 200;
  int deleteStatus = 204;
  int putStatus = 200;
  int issueStatus = 200;
  int templatesStatus = 200;
  int templatePutStatus = 200;
  Map<String, dynamic> importResult = {'created': 0, 'noCustomer': 0, 'noProduct': 0};

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
  http.Request last(String method, String path) => log.lastWhere((r) => r.method == method && r.url.path == path);
  bool has(String method, String path) => log.any((r) => r.method == method && r.url.path == path);

  http.Response _err(int status, String detail) => _json({'title': 'Erro', 'detail': detail, 'status': status}, status);

  late final client = MockClient((r) async {
    log.add(r);
    final p = r.url.path;
    final m = r.method;
    if (p == '/api/sales/certificates' && m == 'GET') return _json(_page(certs));
    if (p == '/api/sales/certificates' && m == 'POST') return _json(_cert(), 201);
    if (p == '/api/sales/certificates/templates' && m == 'GET') {
      if (templatesStatus != 200) return _err(templatesStatus, 'Modelos indisponíveis');
      return _json(templates);
    }
    if (p == '/api/sales/certificates/templates/import-legacy') return _json(importResult);
    if (p.startsWith('/api/sales/certificates/templates/') && m == 'PUT') {
      if (templatePutStatus != 200) return _err(templatePutStatus, 'Modelo inválido');
      return _json({'id': 4});
    }
    if (p.startsWith('/api/sales/certificates/templates/') && m == 'DELETE') return http.Response('', 204);
    if (p == '/api/sales/certificates/7' && m == 'GET') {
      if (certStatus != 200) return _err(certStatus, 'Certificado indisponível');
      return _json(cert);
    }
    if (p == '/api/sales/certificates/7' && m == 'PUT') {
      if (putStatus != 200) return _err(putStatus, 'Quantidade acima da entrega');
      return _json({...cert, 'quantity': 400});
    }
    if (p == '/api/sales/certificates/7' && m == 'DELETE') {
      if (deleteStatus == 204) return http.Response('', 204);
      return _err(deleteStatus, 'Certificado em uso');
    }
    if (p == '/api/sales/certificates/7/issue') return issueStatus == 200 ? _json(_cert(status: 'Issued', found: true)) : _err(issueStatus, 'Certificado em uso');
    if (p == '/api/sales/certificates/7/cancel') return _json(_cert(status: 'Cancelled', cancelReason: 'Erro de digitação'));
    if (p == '/api/sales/certificates/7/link-delivery') return _json(_cert(status: 'Issued', found: true, deliveryId: 2));
    if (p == '/api/sales/orders/3') return _json({'deliveries': deliveries});
    return _json(_page([]));
  });
}

Future<Session> _pump(WidgetTester tester, _Fake fake, Widget Function(Session s) screen) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: fake.client, token: 'tok'))
    ..username = 'ana'
    ..role = fake.role
    ..permissions = rolePermissions[fake.role]!;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: screen(session),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _pushed(WidgetTester tester, _Fake fake, Widget Function(Session s) screen) async {
  await _pump(
    tester,
    fake,
    (s) => Builder(
      builder: (c) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => screen(s))),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  group('lista', () {
    testWidgets('filters change the query, the row opens the certificate and the chip opens the templates', (tester) async {
      final fake = _Fake()
        ..certs = [
          {..._cert(), 'invoiceNumber': '4321'},
        ];
      await _pump(tester, fake, (s) => Scaffold(body: CertificatesScreen(session: s)));
      expect(find.text('5176-26'), findsOneWidget);
      expect(find.text('Rascunho'), findsOneWidget);
      expect(find.text('413 KG'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-Situação')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emitido').last);
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/sales/certificates').url.queryParameters['status'], 'Issued');
      await tester.tap(find.byKey(const ValueKey('filter-Empresa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BST').last);
      await tester.pumpAndSettle();
      expect(fake.last('GET', '/api/sales/certificates').url.queryParameters['company'], 'BST');

      await tester.tap(find.byKey(const ValueKey('certificate-templates')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nenhum modelo ainda'), findsOneWidget);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('5176-26'));
      await tester.pumpAndSettle();
      expect(find.text('Certificado 5176-26 · Incodiesel'), findsOneWidget);
      final loads = fake.log.where((r) => r.url.path == '/api/sales/certificates' && r.method == 'GET').length;
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(fake.log.where((r) => r.url.path == '/api/sales/certificates' && r.method == 'GET').length, greaterThan(loads));
    });
  });

  group('novo certificado', () {
    Future<void> launch(WidgetTester tester, _Fake fake, Map<String, dynamic> order, {int? deliveryId, Set<int>? lineIds, Set<int> covered = const {}}) => _pump(
      tester,
      fake,
      (s) => Builder(
        builder: (c) => Scaffold(
          body: TextButton(onPressed: () => newCertificate(c, s, order, deliveryId: deliveryId, lineIds: lineIds, coveredLineIds: covered), child: const Text('novo')),
        ),
      ),
    );

    testWidgets('an order with a single line goes straight to the editor', (tester) async {
      final fake = _Fake();
      await launch(tester, fake, {
        'id': 3,
        'lines': [
          {'id': 11, 'sequence': 1, 'productCode': 'TB-1', 'description': 'Tubo'},
        ],
      }, deliveryId: 2);
      await tester.tap(find.text('novo'));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('POST', '/api/sales/certificates'));
      expect(b, {'orderId': 3, 'orderLineId': 11, 'deliveryId': 2});
      expect(find.text('Certificado 5176-26 · PV 3'), findsOneWidget);
    });

    testWidgets('backing out of the editor without saving discards the draft the server numbered', (tester) async {
      final fake = _Fake();
      await launch(tester, fake, {
        'id': 3,
        'lines': [
          {'id': 11, 'sequence': 1, 'productCode': 'TB-1', 'description': 'Tubo'},
        ],
      });
      await tester.tap(find.text('novo'));
      await tester.pumpAndSettle();
      expect(find.text('Certificado 5176-26 · PV 3'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(fake.log.where((r) => r.method == 'DELETE' && r.url.path.startsWith('/api/sales/certificates/')), hasLength(1));
      expect(find.textContaining('descartado'), findsOneWidget);
    });

    testWidgets('a draft that was saved but could not be issued is kept when the editor is left', (tester) async {
      final fake = _Fake()..issueStatus = 422;
      await launch(tester, fake, {
        'id': 3,
        'lines': [
          {'id': 11, 'sequence': 1, 'productCode': 'TB-1', 'description': 'Tubo'},
        ],
      });
      await tester.tap(find.text('novo'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('found-Chemical-C')), '0,08');
      await tester.enterText(find.byKey(const ValueKey('found-Dimensional-Espessura')), '0,70');
      await tester.enterText(find.byKey(const ValueKey('found-Mechanical-LR')), '310');
      await tester.tap(find.byKey(const ValueKey('cert-save-issue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(fake.has('PUT', '/api/sales/certificates/7'), isTrue);
      expect(find.textContaining('Certificado em uso'), findsOneWidget); // the issue step was refused; the editor stays with the message
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(fake.log.where((r) => r.method == 'DELETE' && r.url.path.startsWith('/api/sales/certificates/')), isEmpty);
    });

    testWidgets('only the lines of the delivery are offered, with the covered ones flagged', (tester) async {
      final fake = _Fake();
      await launch(
        tester,
        fake,
        {
          'id': 3,
          'lines': [
            {'id': 11, 'sequence': 1, 'productCode': 'TB-1', 'description': 'Tubo'},
            {'id': 12, 'sequence': 2, 'productCode': 'TB-2', 'description': 'Tubo B'},
            {'id': 13, 'sequence': 3, 'productCode': 'TB-3', 'description': 'Tubo C'},
          ],
        },
        lineIds: {11, 12},
        covered: {11},
      );
      await tester.tap(find.text('novo'));
      await tester.pumpAndSettle();
      expect(find.text('Certificado de qual item?'), findsOneWidget);
      expect(find.textContaining('1 · TB-1 · Tubo  (já tem certificado)'), findsOneWidget);
      expect(find.textContaining('TB-2'), findsOneWidget);
      expect(find.textContaining('TB-3'), findsNothing);
    });

    testWidgets('an order with several lines asks which item first; dismissing creates nothing', (tester) async {
      final fake = _Fake();
      await launch(tester, fake, {
        'id': 3,
        'lines': [
          {'id': 11, 'sequence': 1, 'productCode': 'TB-1', 'description': 'Tubo A'},
          {'id': 12, 'sequence': 2, 'productCode': 'TB-2', 'description': 'Tubo B'},
        ],
      });
      await tester.tap(find.text('novo'));
      await tester.pumpAndSettle();
      expect(find.text('Certificado de qual item?'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/sales/certificates'), isFalse);
      await tester.tap(find.text('novo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 · TB-2 · Tubo B'));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('POST', '/api/sales/certificates'))['orderLineId'], 12);
      expect(find.text('Certificado 5176-26 · PV 3'), findsOneWidget);
    });
  });

  group('tela do certificado', () {
    testWidgets('a load error is shown', (tester) async {
      final fake = _Fake()..certStatus = 500;
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      expect(find.text('Certificado'), findsOneWidget);
      expect(find.textContaining('Certificado indisponível'), findsOneWidget);
    });

    testWidgets('a draft shows its tables and next step; Sales can fill but not issue', (tester) async {
      final fake = _Fake()..role = 'Sales';
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      expect(find.text('Certificado de qualidade · BST'), findsOneWidget);
      expect(find.text('Rascunho'), findsWidgets);
      expect(find.text('Máx. 0,150'), findsOneWidget);
      expect(find.text('0,65 a 0,75'), findsOneWidget);
      expect(find.text('290 Mpa mín.'), findsOneWidget);
      expect(find.byKey(const ValueKey('certificate-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('certificate-issue')), findsNothing);
      // Without the issue permission the menu offers only the edit.
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Excluir rascunho'), findsNothing);
      expect(find.text('Cancelar certificado'), findsNothing);
    });

    testWidgets('a reader sees the certificate without actions', (tester) async {
      final fake = _Fake()..role = 'Reader';
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      expect(find.byKey(const ValueKey('certificate-edit')), findsNothing);
      expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
      expect(find.byKey(const ValueKey('certificate-print')), findsOneWidget);
    });

    testWidgets('issuing without any found value explains and opens the editor', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      await tester.tap(find.byKey(const ValueKey('certificate-issue')));
      await tester.pumpAndSettle();
      expect(find.text('Faltam os valores encontrados'), findsOneWidget);
      expect(find.textContaining('Faltam: C, Espessura, LR'), findsOneWidget);
      await tester.tap(find.text('Preencher').last);
      await tester.pumpAndSettle();
      expect(find.text('Dados do certificado'), findsOneWidget);
      expect(fake.has('POST', '/api/sales/certificates/7/issue'), isFalse);
    });

    testWidgets('issuing asks for confirmation, then shows the issued certificate', (tester) async {
      final fake = _Fake()..cert = _cert(found: true);
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      await tester.tap(find.byKey(const ValueKey('certificate-issue')));
      await tester.pumpAndSettle();
      expect(find.text('Emitir certificado 5176-26?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/sales/certificates/7/issue'), isFalse);
      await tester.tap(find.byKey(const ValueKey('certificate-issue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/sales/certificates/7/issue'), isTrue);
      expect(find.text('Emitido'), findsWidgets);
      expect(find.byKey(const ValueKey('certificate-link')), findsOneWidget);
      expect(find.text('0,08'), findsOneWidget);
    });

    testWidgets('a draft offers only "Excluir rascunho"; "Cancelar certificado" is for an issued one', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      expect(find.text('Excluir rascunho'), findsOneWidget);
      expect(find.text('Cancelar certificado'), findsNothing);
    });

    testWidgets('an issued certificate without delivery warns when the order has none', (tester) async {
      final fake = _Fake()..cert = _cert(status: 'Issued', found: true);
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      await tester.tap(find.byKey(const ValueKey('certificate-link')));
      await tester.pumpAndSettle();
      expect(find.text('O pedido ainda não tem entrega programada'), findsOneWidget);
      expect(fake.has('POST', '/api/sales/certificates/7/link-delivery'), isFalse);
    });

    testWidgets('linking picks a delivery, ignores cancelled ones and shows the new link', (tester) async {
      final fake = _Fake()
        ..cert = _cert(status: 'Issued', found: true)
        ..deliveries = [
          {'id': 2, 'reference': 'ENT 2', 'plannedDate': '2026-11-05', 'invoiceNumber': '4321', 'status': 'Planned'},
          {'id': 3, 'reference': 'ENT 3', 'plannedDate': '2026-11-06', 'invoiceNumber': null, 'status': 'Cancelled'},
        ];
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      await tester.tap(find.byKey(const ValueKey('certificate-link')));
      await tester.pumpAndSettle();
      expect(find.text('Vincular a qual entrega?'), findsOneWidget);
      expect(find.textContaining('ENT 3'), findsNothing);
      await tester.tap(find.text('ENT 2 · 05/11/2026 · NF 4321'));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('POST', '/api/sales/certificates/7/link-delivery'))['deliveryId'], 2);
      expect(find.text('Certificado vinculado à entrega'), findsOneWidget);
      expect(find.byKey(const ValueKey('certificate-link')), findsNothing);
      expect(find.textContaining('Vinculado a ENT 2'), findsOneWidget);
      expect(find.text('Ver entrega'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await _menu(tester, 'Trocar entrega');
      expect(find.text('Vincular a qual entrega?'), findsOneWidget);
    });

    testWidgets('cancelling an issued certificate asks for a reason and shows the cancelled state', (tester) async {
      final fake = _Fake()..cert = _cert(status: 'Issued', found: true, deliveryId: 2);
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      await _menu(tester, 'Cancelar certificado');
      expect(find.text('Cancelar 5176-26?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-step'))); // disabled until a reason is typed
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/sales/certificates/7/cancel'), isFalse);
      await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Erro de digitação');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('POST', '/api/sales/certificates/7/cancel'))['reason'], 'Erro de digitação');
      expect(find.text('Cancelado'), findsWidgets);
      expect(find.text('Erro de digitação'), findsOneWidget);
      expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
    });

    testWidgets('deleting a draft confirms and goes back; an API refusal is shown', (tester) async {
      final fake = _Fake()..deleteStatus = 409;
      await _pushed(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      await _menu(tester, 'Excluir rascunho');
      expect(find.text('Excluir rascunho 5176-26?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Certificado em uso'), findsOneWidget);
      expect(find.text('Certificado 5176-26 · Incodiesel'), findsOneWidget);

      fake.deleteStatus = 204;
      await tester.pump(const Duration(seconds: 5));
      await _menu(tester, 'Excluir rascunho');
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('the refresh button reloads the certificate and a failed reload is announced', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      int loads() => fake.log.where((r) => r.method == 'GET' && r.url.path == '/api/sales/certificates/7').length;
      final first = loads();
      await tester.tap(find.byKey(const ValueKey('record-refresh')));
      await tester.pumpAndSettle();
      expect(loads(), first + 1);
      fake.certStatus = 500;
      await tester.tap(find.byKey(const ValueKey('record-refresh')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Falha ao atualizar'), findsOneWidget);
      expect(find.text('Certificado 5176-26 · Incodiesel'), findsOneWidget);
    });

    testWidgets('editing from the menu returns the saved certificate to the screen', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateScreen(session: s, id: 7));
      await _menu(tester, 'Editar');
      await tester.enterText(find.byKey(const ValueKey('cert-quantity')), '400');
      await tester.tap(find.byKey(const ValueKey('cert-save')));
      await tester.pumpAndSettle();
      expect(find.text('400 KG'), findsOneWidget);
    });
  });

  group('editor', () {
    testWidgets('invalid date and quantity are rejected before calling the API', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateEditorScreen(session: s, certificate: _cert()));
      await tester.enterText(find.byKey(const ValueKey('cert-issueDate')), '31/02/2026');
      await tester.tap(find.byKey(const ValueKey('cert-save')));
      await tester.pumpAndSettle();
      expect(find.text('Data inválida'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('cert-issueDate')), '30/10/2026');
      await tester.enterText(find.byKey(const ValueKey('cert-quantity')), '0');
      await tester.tap(find.byKey(const ValueKey('cert-save')));
      await tester.pumpAndSettle();
      expect(find.text('Quantidade deve ser maior que zero'), findsOneWidget);
      expect(fake.has('PUT', '/api/sales/certificates/7'), isFalse);
    });

    testWidgets('a draft without a description is refused before the API and the message is announced at the top', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateEditorScreen(session: s, certificate: _cert()));
      await tester.enterText(find.byKey(const ValueKey('cert-description')), '');
      await tester.tap(find.byKey(const ValueKey('cert-save')));
      await tester.pumpAndSettle();
      expect(find.text('Informe a descrição do produto'), findsOneWidget);
      expect(fake.has('PUT', '/api/sales/certificates/7'), isFalse);
    });

    testWidgets('Salvar e emitir needs a found value on every row, naming the empty ones; confirms, then saves and issues in that order', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateEditorScreen(session: s, certificate: _cert()));
      await tester.tap(find.byKey(const ValueKey('cert-save-issue')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Faltam: C, Espessura, LR'), findsOneWidget);
      expect(fake.has('PUT', '/api/sales/certificates/7'), isFalse);
      // One row filled is not enough: the server wants every row.
      await tester.enterText(find.byKey(const ValueKey('found-Chemical-C')), '0,08');
      await tester.tap(find.byKey(const ValueKey('cert-save-issue')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Faltam: Espessura, LR'), findsOneWidget);
      expect(fake.has('PUT', '/api/sales/certificates/7'), isFalse);
      await tester.enterText(find.byKey(const ValueKey('found-Dimensional-Espessura')), '0,70');
      await tester.enterText(find.byKey(const ValueKey('found-Mechanical-LR')), '-'); // "-" is a value for the server, so it is one here
      await tester.tap(find.byKey(const ValueKey('cert-save-issue')));
      await tester.pumpAndSettle();
      expect(find.text('Salvar e emitir 5176-26?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      await tester.pumpAndSettle();
      final calls = [
        for (final r in fake.log)
          if (r.method != 'GET') '${r.method} ${r.url.path}',
      ];
      expect(calls, ['PUT /api/sales/certificates/7', 'POST /api/sales/certificates/7/issue']);
    });

    testWidgets('only a role that may issue sees Salvar e emitir', (tester) async {
      final fake = _Fake()..role = 'Sales';
      await _pump(tester, fake, (s) => CertificateEditorScreen(session: s, certificate: _cert()));
      expect(find.byKey(const ValueKey('cert-save-issue')), findsNothing);
      expect(find.byKey(const ValueKey('cert-save')), findsOneWidget);
    });

    testWidgets('leaving with unsaved edits asks first', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateEditorScreen(session: s, certificate: _cert()));
      await tester.enterText(find.byKey(const ValueKey('cert-quantity')), '99');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cert-save')), findsOneWidget);
    });

    testWidgets('an API error is shown and the editor stays; the delivery dropdown is sent', (tester) async {
      final fake = _Fake()
        ..putStatus = 422
        ..deliveries = [
          {'id': 2, 'reference': 'ENT 2', 'plannedDate': '2026-11-05', 'invoiceNumber': null, 'status': 'Planned'},
        ];
      await _pump(tester, fake, (s) => CertificateEditorScreen(session: s, certificate: _cert()));
      await tester.ensureVisible(find.byKey(const ValueKey('cert-delivery')));
      await tester.tap(find.byKey(const ValueKey('cert-delivery')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ENT 2 · 05/11/2026').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cert-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Quantidade acima da entrega'), findsOneWidget);
      final b = fake.body(fake.last('PUT', '/api/sales/certificates/7'));
      expect(b['deliveryId'], 2);
      expect(b['issueDate'], '2026-10-30');
      expect(b['quantity'], 413);
      expect(b['title'], isNull);
      expect(find.byKey(const ValueKey('cert-save')), findsOneWidget);
    });

    testWidgets('the found counter follows the typed values and a blank row name is not allowed', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateEditorScreen(session: s, certificate: _cert()));
      expect(find.text('0 de 1 encontrados'), findsNWidgets(3));
      await tester.enterText(find.byKey(const ValueKey('found-Chemical-C')), '0,08');
      await tester.pump();
      expect(find.text('1 de 1 encontrados'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('found-Chemical-C')), '-');
      await tester.pump();
      expect(find.text('1 de 1 encontrados'), findsOneWidget); // "-" is a value, as for the server
      await tester.enterText(find.byKey(const ValueKey('found-Chemical-C')), '  ');
      await tester.pump();
      expect(find.text('1 de 1 encontrados'), findsNothing);
    });

    testWidgets('an existing custom title stays selectable and removing every row shows the empty hint', (tester) async {
      final fake = _Fake();
      final cert = {..._cert(), 'title': 'TÍTULO ESPECIAL'};
      await _pump(tester, fake, (s) => CertificateEditorScreen(session: s, certificate: cert));
      expect(find.text('TÍTULO ESPECIAL'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('row-del-Chemical-C')));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma linha.'), findsOneWidget);
    });
  });

  group('modelos', () {
    testWidgets('a load error is shown', (tester) async {
      final fake = _Fake()..templatesStatus = 500;
      await _pump(tester, fake, (s) => CertificateTemplatesScreen(session: s));
      expect(find.textContaining('Modelos indisponíveis'), findsOneWidget);
    });

    testWidgets('a reader sees the models without edit, forget or import', (tester) async {
      final fake = _Fake()
        ..role = 'Reader'
        ..templates = [_template()];
      await _pump(tester, fake, (s) => CertificateTemplatesScreen(session: s));
      expect(find.byKey(const ValueKey('templates-import')), findsNothing);
      await tester.tap(find.text('Incodiesel · 060.350.60'));
      await tester.pumpAndSettle();
      expect(find.text('Química · C: Máx. 0,150'), findsOneWidget);
      expect(find.text('Mecânico · LR: -'), findsOneWidget);
      expect(find.byKey(const ValueKey('template-edit-4')), findsNothing);
      expect(find.byKey(const ValueKey('template-forget-4')), findsNothing);
    });

    testWidgets('importing from Excel reports when nothing is new and when models were created', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, (s) => CertificateTemplatesScreen(session: s));
      await tester.tap(find.byKey(const ValueKey('templates-import')));
      await tester.pumpAndSettle();
      expect(find.text('Nada novo: os modelos dos certificados em Excel já estão carregados.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      fake.importResult = {'created': 12, 'noCustomer': 3, 'noProduct': 2};
      fake.templates = [_template()];
      await tester.tap(find.byKey(const ValueKey('templates-import')));
      await tester.pumpAndSettle();
      expect(find.text('12 modelos criados a partir dos certificados em Excel (3 sem cliente cadastrado, 2 sem produto cadastrado).'), findsOneWidget);
      expect(find.text('Incodiesel · 060.350.60'), findsOneWidget);
    });

    testWidgets('keeping a model on the forget dialog sends nothing', (tester) async {
      final fake = _Fake()..templates = [_template()];
      await _pump(tester, fake, (s) => CertificateTemplatesScreen(session: s));
      await tester.tap(find.text('Incodiesel · 060.350.60'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('template-forget-4')));
      await tester.pumpAndSettle();
      expect(find.text('Esquecer este modelo?'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(fake.log.any((r) => r.method == 'DELETE'), isFalse);
    });

    testWidgets('the editor rejects a blank row name, shows API errors, changes kind, removes rows and saves everything', (tester) async {
      final fake = _Fake()..templates = [_template()];
      await _pump(tester, fake, (s) => CertificateTemplatesScreen(session: s));
      await tester.tap(find.text('Incodiesel · 060.350.60'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('template-edit-4')));
      await tester.pumpAndSettle();
      expect(find.text('Modelo · Incodiesel · 060.350.60'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('template-add-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('template-save')));
      await tester.pumpAndSettle();
      expect(find.text('Toda linha precisa de um nome'), findsOneWidget);
      expect(fake.has('PUT', '/api/sales/certificates/templates/4'), isFalse);

      // Remove the blank row (third), keep the others.
      await tester.tap(find.byTooltip('Remover').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('template-title')), 'CERTIFICADO ESPECIAL');
      // Change the kind of the first row to Dimensional.
      await tester.tap(find.text('Química').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dimensional').last);
      await tester.pumpAndSettle();

      fake.templatePutStatus = 422;
      await tester.tap(find.byKey(const ValueKey('template-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Modelo inválido'), findsOneWidget);

      fake.templatePutStatus = 200;
      await tester.tap(find.byKey(const ValueKey('template-save')));
      await tester.pumpAndSettle();
      final b = fake.body(fake.last('PUT', '/api/sales/certificates/templates/4'));
      expect(b['title'], 'CERTIFICADO ESPECIAL');
      expect(b['finish'], 'Liso');
      final measures = (b['measures'] as List).cast<Map<String, dynamic>>();
      expect(measures.map((m) => m['name']), ['C', 'LR']);
      expect(measures.first['kind'], 'Dimensional');
      expect(find.text('Modelo salvo'), findsOneWidget);
    });

    testWidgets('cancelling the template editor discards the changes', (tester) async {
      final fake = _Fake()..templates = [_template()];
      await _pump(tester, fake, (s) => CertificateTemplatesScreen(session: s));
      await tester.tap(find.text('Incodiesel · 060.350.60'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('template-edit-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Modelo salvo'), findsNothing);
      expect(fake.has('PUT', '/api/sales/certificates/templates/4'), isFalse);
    });
  });
}
