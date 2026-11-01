import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/settings/settings_admin.dart';
import 'package:ebt_engenharia/screens/settings/settings_backup.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _settings({Object? agentSeenAt = 'now', bool enabled = true, String frequency = 'Daily', Object? destination, bool? lastRunOk = true}) => {
  'enabled': enabled,
  'frequency': frequency,
  'timeOfDay': '22:00',
  'weekday': 1,
  'destination': destination,
  'keep': 14,
  'runRequestedAt': null,
  'lastRunAt': DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String(),
  'lastRunOk': lastRunOk,
  'lastRunMessage': 'Cópia ebt-1.dump criada',
  'agentSeenAt': agentSeenAt == 'now' ? DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String() : agentSeenAt,
  'nextRunAt': DateTime.now().toUtc().add(const Duration(hours: 5)).toIso8601String(),
};

Future<(Session, List<http.Request>)> _pump(WidgetTester tester, Map<String, dynamic> initial, {Widget Function(Session)? home, int putStatus = 200}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = <http.Request>[];
  var current = initial;
  final client = MockClient((r) async {
    log.add(r);
    if (r.url.path == '/api/admin/backup-status') return _json({'configured': false, 'count': 0});
    if (r.url.path == '/api/admin/backup-settings' && r.method == 'PUT') {
      if (putStatus != 200) return _json({'title': 'Dados inválidos', 'status': putStatus, 'errors': {'keep': ['Valor inválido']}}, putStatus);
      current = {...current, ...jsonDecode(r.body) as Map<String, dynamic>};
      return _json(current);
    }
    if (r.url.path == '/api/admin/backup-settings/run-now') return _json({...current, 'runRequestedAt': DateTime.now().toUtc().toIso8601String()});
    return _json(current);
  });
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
    ..username = 'ana'
    ..role = 'Admin';
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: SingleChildScrollView(child: home?.call(session) ?? BackupSettingsView(session: session))),
    ),
  );
  await tester.pumpAndSettle();
  return (session, log);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads the schedule and the status', (tester) async {
    await _pump(tester, _settings(destination: r'D:\backups'));
    expect(find.text('Backup automático'), findsOneWidget);
    expect(find.text('Todo dia'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('D:\\backups'), findsOneWidget);
    expect(find.textContaining('Último backup deu certo'), findsOneWidget);
    expect(find.text('Cópia ebt-1.dump criada'), findsOneWidget);
    expect(find.textContaining('Próximo:'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-agent-warning')), findsNothing);
    expect(find.byKey(const ValueKey('backup-weekday')), findsNothing);
  });

  testWidgets('edits and saves: the PUT carries the form', (tester) async {
    final (_, log) = await _pump(tester, _settings());
    await _tap(tester, find.byKey(const ValueKey('backup-frequency')));
    await _tap(tester, find.text('Toda semana').last);
    expect(find.byKey(const ValueKey('backup-weekday')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('backup-weekday')));
    await _tap(tester, find.text('Sexta-feira').last);
    await tester.enterText(find.byKey(const ValueKey('backup-destination')), r'\\srv\bk');
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '30');
    await _tap(tester, find.byKey(const ValueKey('backup-save')));
    final put = log.singleWhere((r) => r.method == 'PUT');
    expect(jsonDecode(put.body), {'enabled': true, 'frequency': 'Weekly', 'timeOfDay': '22:00', 'weekday': 5, 'destination': r'\\srv\bk', 'keep': 30});
    expect(find.text('Configuração salva'), findsOneWidget);
  });

  testWidgets('picks the time, switches off, hourly hides the time and empty destination is null', (tester) async {
    final (_, log) = await _pump(tester, _settings());
    await _tap(tester, find.byKey(const ValueKey('backup-time')));
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '6');
    await tester.enterText(fields.at(1), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('06:30'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('backup-enabled')));
    await _tap(tester, find.byKey(const ValueKey('backup-frequency')));
    await _tap(tester, find.text('A cada hora').last);
    expect(find.byKey(const ValueKey('backup-time')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('backup-save')));
    final body = jsonDecode(log.singleWhere((r) => r.method == 'PUT').body) as Map<String, dynamic>;
    expect(body['enabled'], isFalse);
    expect(body['frequency'], 'Hourly');
    expect(body['timeOfDay'], '06:30');
    expect(body['destination'], isNull);
  });

  testWidgets('invalid number of copies is not sent; a server error is shown', (tester) async {
    final (_, log) = await _pump(tester, _settings(), putStatus: 400);
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '0');
    await _tap(tester, find.byKey(const ValueKey('backup-save')));
    expect(find.text('Informe de 1 a 365 cópias para guardar.'), findsOneWidget);
    expect(log.where((r) => r.method == 'PUT'), isEmpty);
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '20');
    await _tap(tester, find.byKey(const ValueKey('backup-save')));
    expect(log.where((r) => r.method == 'PUT'), hasLength(1));
    expect(find.text('Configuração salva'), findsNothing);
  });

  testWidgets('Fazer backup agora posts run-now and says when it starts', (tester) async {
    final (_, log) = await _pump(tester, _settings());
    await _tap(tester, find.byKey(const ValueKey('backup-run-now')));
    expect(log.where((r) => r.method == 'POST' && r.url.path == '/api/admin/backup-settings/run-now'), hasLength(1));
    expect(find.text('Pedido enviado. O backup começa em até 5 minutos.'), findsOneWidget);
    expect(find.textContaining('Pedido de backup agora aguardando'), findsOneWidget);
  });

  testWidgets('warns when the agent never called in or is late; failed run is flagged', (tester) async {
    await _pump(tester, _settings(agentSeenAt: null, lastRunOk: false));
    expect(find.byKey(const ValueKey('backup-agent-warning')), findsOneWidget);
    expect(find.textContaining('install-backup-agent.ps1'), findsOneWidget);
    expect(find.textContaining('Último backup falhou'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _settings(agentSeenAt: DateTime.now().toUtc().subtract(const Duration(minutes: 40)).toIso8601String()));
    expect(find.byKey(const ValueKey('backup-agent-warning')), findsOneWidget);
  });

  testWidgets('Administração links to the view', (tester) async {
    await _pump(tester, _settings(), home: (s) => AdminSection(session: s, open: (title, builder) => Navigator.of(tester.element(find.byType(Scaffold).first)).push(MaterialPageRoute<void>(builder: (c) => Scaffold(body: SingleChildScrollView(child: builder(c))))),));
    await _tap(tester, find.byKey(const ValueKey('settings-open-backup')));
    expect(find.byType(BackupSettingsView), findsOneWidget);
  });
}