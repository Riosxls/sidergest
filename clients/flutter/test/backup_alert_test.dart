import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/dashboard.dart';
import 'package:ebt_engenharia/screens/settings/settings_dialog.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

String _ago(Duration d) => DateTime.now().subtract(d).toUtc().toIso8601String();

Future<void> _pump(WidgetTester tester, {String role = 'Admin', Map<String, dynamic>? backup, bool fail = false}) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = MockClient((r) async {
    final p = r.url.path;
    if (p == '/api/admin/backup-settings') {
      if (fail) return http.Response('boom', 500);
      return _json({'enabled': false, 'frequency': 'Daily', 'timeOfDay': '22:00', 'weekday': 0, 'keep': 14, ...?backup});
    }
    if (p == '/api/stock/closings' || p == '/api/purchasing/overdue' || p == '/api/production/outside-shipments' || p == '/api/production/load') {
      return _json([]);
    }
    return _json({'items': [], 'total': 0, 'skip': 0, 'take': 50});
  });
  final session =
      Session(
          api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'),
        )
        ..username = 'ana'
        ..role = role
        ..permissions = rolePermissions[role]!;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: DashboardScreen(session: session)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final key = find.byKey(const ValueKey('alert-backup'));

  testWidgets('failed last run is shown', (tester) async {
    await _pump(
      tester,
      backup: {
        'enabled': true,
        'lastRunOk': false,
        'lastRunMessage': 'Disco cheio.',
        'lastRunAt': _ago(const Duration(hours: 1)),
        'agentSeenAt': _ago(const Duration(minutes: 1)),
      },
    );
    expect(key, findsOneWidget);
    expect(find.text('Último backup falhou'), findsOneWidget);
    expect(find.text('Disco cheio.'), findsOneWidget);
  });

  testWidgets('silent backup program is shown', (tester) async {
    await _pump(
      tester,
      backup: {'enabled': true, 'lastRunOk': true, 'lastRunAt': _ago(const Duration(hours: 1)), 'agentSeenAt': _ago(const Duration(minutes: 30))},
    );
    expect(find.text('Programa de backup parado'), findsOneWidget);
  });

  testWidgets('a recent manual request with no program is shown even when automatic backup is off', (tester) async {
    await _pump(tester, backup: {'enabled': false, 'runRequestedAt': _ago(const Duration(hours: 2))});
    expect(find.text('Programa de backup parado'), findsOneWidget);
  });

  testWidgets('stale backup shows its age', (tester) async {
    await _pump(
      tester,
      backup: {'enabled': true, 'lastRunOk': true, 'lastRunAt': _ago(const Duration(hours: 50)), 'agentSeenAt': _ago(const Duration(minutes: 1))},
    );
    expect(find.text('Backup atrasado'), findsOneWidget);
    expect(find.textContaining('Último backup há 50 horas'), findsOneWidget);
  });

  testWidgets('no backup yet is reported', (tester) async {
    await _pump(tester, backup: {'enabled': true, 'agentSeenAt': _ago(const Duration(minutes: 1))});
    expect(find.text('Nenhum backup feito ainda.'), findsOneWidget);
  });

  testWidgets('hidden when healthy, off, cancelled, non-admin or failing', (tester) async {
    final healthy = {'enabled': true, 'lastRunOk': true, 'lastRunAt': _ago(const Duration(hours: 2)), 'agentSeenAt': _ago(const Duration(minutes: 1))};
    await _pump(tester, backup: healthy);
    expect(key, findsNothing);
    await _pump(tester, backup: {'enabled': false});
    expect(key, findsNothing);
    await _pump(tester, backup: {...healthy, 'lastRunOk': false, 'lastRunMessage': 'Backup cancelado.'});
    expect(key, findsNothing);
    await _pump(tester, role: 'Production', backup: {'enabled': true, 'lastRunOk': false, 'lastRunMessage': 'x'});
    expect(key, findsNothing);
    await _pump(tester, fail: true);
    expect(key, findsNothing);
  });

  testWidgets('tapping the alert opens the settings dialog', (tester) async {
    await _pump(tester, backup: {'enabled': true, 'lastRunOk': false, 'lastRunMessage': 'Erro.', 'agentSeenAt': _ago(const Duration(minutes: 1))});
    await tester.tap(key);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
  });
}
