import 'dart:convert';
import 'dart:typed_data';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/legacy_cleanup.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  testWidgets('legacy cleanup previews before it changes anything and asks before cancelling', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final log = <http.Request>[];
    final client = MockClient((r) async {
      log.add(r);
      if (r.method == 'GET') return _json({'templates': 0, 'operations': 0, 'customers': 0, 'firstDate': null, 'lastDate': null});
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final apply = body['apply'] == true;
      if (r.url.path == '/api/production/orders/bulk/suggest-process') return _json({'matched': 40, 'done': apply ? 40 : 0, 'skipped': 0, 'sample': []});
      return _json({'matched': 929, 'done': apply ? 929 : 0, 'skipped': 0, 'sample': ['OF 1', 'OF 2']});
    });
    final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
      ..username = 'admin'
      ..role = 'Admin'
      ..permissions = rolePermissions['Admin']!;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(builder: (c) => TextButton(onPressed: () => showLegacyCleanupDialog(c, session), child: const Text('abrir'))),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('legacy-process-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Gerar em 40 OFs'), findsOneWidget);
    expect(jsonDecode(log.last.body)['apply'], false);
    await tester.tap(find.byKey(const ValueKey('legacy-process-apply')));
    await tester.pumpAndSettle();
    expect(jsonDecode(log.last.body)['apply'], true);
    expect(find.text('Processo sugerido escrito em 40 OFs.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('legacy-stale-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar 929 OFs'), findsOneWidget);
    final before = log.length;
    await tester.tap(find.byKey(const ValueKey('legacy-stale-apply')));
    await tester.pumpAndSettle();
    expect(log.length, before, reason: 'asks for confirmation first');
    await tester.tap(find.byKey(const ValueKey('confirm-cancel-stale')));
    await tester.pumpAndSettle();
    final sent = jsonDecode(log.last.body) as Map<String, dynamic>;
    expect(sent['apply'], true);
    expect(sent['olderThanDays'], 90);
    expect(find.text('929 OFs canceladas.'), findsOneWidget);
  });

  Future<List<http.Request>> open(WidgetTester tester, http.Response Function(http.Request) handler) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final log = <http.Request>[];
    final client = MockClient((r) async {
      log.add(r);
      return handler(r);
    });
    final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
      ..username = 'admin'
      ..role = 'Admin'
      ..permissions = rolePermissions['Admin']!;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(builder: (c) => TextButton(onPressed: () => showLegacyCleanupDialog(c, session), child: const Text('abrir'))),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return log;
  }

  testWidgets('complete requirements previews, asks and then applies', (tester) async {
    final log = await open(tester, (r) {
      if (r.method == 'GET') return _json({'templates': 0, 'operations': 0, 'customers': 0, 'firstDate': null, 'lastDate': null});
      final apply = (jsonDecode(r.body) as Map)['apply'] == true;
      return _json({'matched': 120, 'done': apply ? 118 : 0, 'skipped': apply ? 2 : 0, 'sample': ['OF 1', 'OF 2'], 'operationsFilled': 300});
    });
    await tester.tap(find.byKey(const ValueKey('legacy-complete-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Completar 120 OFs'), findsOneWidget);
    expect(find.text('300 operações a preencher.'), findsOneWidget);
    expect(find.textContaining('Exemplos: OF 1, OF 2'), findsOneWidget);
    expect(jsonDecode(log.last.body)['apply'], false);
    final before = log.length;
    await tester.tap(find.byKey(const ValueKey('legacy-complete-apply')));
    await tester.pumpAndSettle();
    expect(log.length, before, reason: 'asks for confirmation first');
    await tester.tap(find.byKey(const ValueKey('confirm-complete-requirements')));
    await tester.pumpAndSettle();
    expect(log.last.url.path, '/api/production/orders/bulk/complete-requirements');
    expect(jsonDecode(log.last.body)['apply'], true);
    expect(find.text('118 OFs completadas (300 operações preenchidas) · 2 puladas.'), findsOneWidget);
  });

  testWidgets('process templates: empty summary explains, import uploads the CSV and shows counts and skipped reasons', (tester) async {
    final oldPicker = processTemplateFilePicker;
    processTemplateFilePicker = () async => (name: 'modelos.csv', bytes: Uint8List.fromList(utf8.encode('a;b\n1;2')));
    addTearDown(() => processTemplateFilePicker = oldPicker);
    var imported = false;
    final log = await open(tester, (r) {
      if (r.method == 'GET') {
        return imported
            ? _json({'templates': 80, 'operations': 400, 'customers': 12, 'firstDate': '2023-03-10', 'lastDate': '2026-09-02'})
            : _json({'templates': 0, 'operations': 0, 'customers': 0, 'firstDate': null, 'lastDate': null});
      }
      imported = true;
      return _json({'read': 100, 'templates': 80, 'updated': 5, 'operations': 400, 'skipped': 7, 'skippedReasons': {'medidas': 4, 'operação': 2, 'data': 1}, 'firstDate': '2023-03-10', 'lastDate': '2026-09-02'});
    });
    expect(find.textContaining('Nenhum modelo importado ainda'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('legacy-templates-import')));
    await tester.pumpAndSettle();
    final post = log.lastWhere((r) => r.method == 'POST');
    expect(post.url.path, '/api/production/process-templates/import');
    expect(post.headers['content-type'], contains('multipart/form-data'));
    expect(find.text('Modelos importados'), findsOneWidget);
    expect(find.text('Linhas lidas: 100'), findsOneWidget);
    expect(find.text('Ignoradas: 7'), findsOneWidget);
    expect(find.text('Motivos: 4 sem medidas válidas, 2 sem operação válida, 1 com data inválida'), findsOneWidget);
    await tester.tap(find.text('Fechar').last);
    await tester.pumpAndSettle();
    expect(find.text('80 modelos, 400 operações, de mar/2023 a set/2026'), findsOneWidget);
  });
}
