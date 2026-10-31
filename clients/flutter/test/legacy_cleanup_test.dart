import 'dart:convert';

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
}
