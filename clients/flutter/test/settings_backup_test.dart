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

Map<String, dynamic> _settings({Object? agentSeenAt = 'now', bool enabled = true, String frequency = 'Daily', Object? destination = r'D:\backups', bool? lastRunOk = true}) => {
  'enabled': enabled,
  'frequency': frequency,
  'timeOfDay': '22:00',
  'weekday': 1,
  'destination': destination,
  'keep': 3,
  'runRequestedAt': null,
  'lastRunAt': DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String(),
  'lastRunOk': lastRunOk,
  'lastRunMessage': 'Cópia ebt-1.dump criada',
  'agentSeenAt': agentSeenAt == 'now' ? DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String() : agentSeenAt,
  'nextRunAt': DateTime.now().toUtc().add(const Duration(hours: 5)).toIso8601String(),
};

/// When set, GET answers with this instead of the stored settings (lets a test move the server state).
Map<String, dynamic>? _live;
bool _failGet = false;
bool _failCancel = false;

Future<(Session, List<http.Request>)> _pump(
  WidgetTester tester,
  Map<String, dynamic> initial, {
  Widget Function(Session)? home,
  int putStatus = 200,
  String putErrorField = 'keep',
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = <http.Request>[];
  var current = initial;
  _live = null;
  _failGet = false;
  _failCancel = false;
  final client = MockClient((r) async {
    log.add(r);
    if (r.url.path == '/api/admin/backup-status') return _json({'configured': false, 'count': 0});
    if (r.url.path == '/api/admin/backup-settings' && r.method == 'PUT') {
      if (putStatus != 200) {
        return _json({
          'title': 'Dados inválidos',
          'status': putStatus,
          'errors': {
            putErrorField: [putErrorField == 'destination' ? 'Informe a pasta de destino.' : 'Valor inválido'],
          },
        }, putStatus);
      }
      current = {...current, ...jsonDecode(r.body) as Map<String, dynamic>};
      return _json(current);
    }
    if (r.url.path == '/api/admin/backup-settings/run-now') return _json({...current, 'runRequestedAt': DateTime.now().toUtc().toIso8601String()});
    if (r.url.path == '/api/admin/backup-settings/cancel') {
      if (_failCancel) return _json({'title': 'Sem permissão'}, 500);
      final asked = DateTime.now().toUtc().add(const Duration(seconds: 1)).toIso8601String();
      current = {...(_live ?? current), 'cancelRequestedAt': asked, 'progress': _progress(30, backupCancellingStage)};
      _live = current;
      return _json(current);
    }
    if (_failGet && r.method == 'GET') return _json({'title': 'Erro'}, 500);
    return _json(_live ?? current);
  });
  final session =
      Session(
          api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'),
        )
        ..username = 'ana'
        ..role = 'Admin';
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: SingleChildScrollView(child: home?.call(session) ?? BackupSettingsView(session: session)),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return (session, log);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Map<String, dynamic> _progress(int percent, String? stage, {bool running = true}) => {
  'running': running,
  'percent': percent,
  'stage': stage,
  'startedAt': null,
  'updatedAt': null,
};

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  drillTests();
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
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '2');
    await _tap(tester, find.byKey(const ValueKey('backup-save')));
    final put = log.singleWhere((r) => r.method == 'PUT');
    expect(jsonDecode(put.body), {'enabled': true, 'frequency': 'Weekly', 'timeOfDay': '22:00', 'weekday': 5, 'destination': r'\\srv\bk', 'keep': 2});
    expect(find.text('Configuração salva'), findsOneWidget);
  });

  testWidgets('picks the time, switches off, hourly hides the time and empty destination is null', (tester) async {
    final (_, log) = await _pump(tester, _settings(destination: null));
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

  testWidgets('copies are limited to 1..5: 6 is not sent, letters are dropped, info line is shown', (tester) async {
    final (_, log) = await _pump(tester, _settings());
    expect(find.byKey(const ValueKey('backup-limit-info')), findsOneWidget);
    expect(find.text('O sistema guarda no máximo 5 backups. Ao fazer um novo com 5 já guardados, o mais antigo é substituído.'), findsOneWidget);
    expect(find.text('De 1 a 5'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '6');
    await _tap(tester, find.byKey(const ValueKey('backup-save')));
    expect(find.text('Informe de 1 a 5.'), findsOneWidget);
    expect(log.where((r) => r.method == 'PUT'), isEmpty);
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '1a');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('backup-keep'))).controller!.text, '1');
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '5');
    await _tap(tester, find.byKey(const ValueKey('backup-save')));
    expect(jsonDecode(log.singleWhere((r) => r.method == 'PUT').body)['keep'], 5);
  });

  testWidgets('a value above 5 from an old server is clamped to 5 and the form stays clean', (tester) async {
    await _pump(tester, {..._settings(), 'keep': 14});
    expect(tester.widget<TextField>(find.byKey(const ValueKey('backup-keep'))).controller!.text, '5');
    await _unmount(tester);
  });

  testWidgets('invalid number of copies is not sent; a server error is shown', (tester) async {
    final (_, log) = await _pump(tester, _settings(), putStatus: 400);
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '0');
    await _tap(tester, find.byKey(const ValueKey('backup-save')));
    expect(find.text('Informe de 1 a 5.'), findsOneWidget);
    expect(log.where((r) => r.method == 'PUT'), isEmpty);
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '4');
    await _tap(tester, find.byKey(const ValueKey('backup-save')));
    expect(log.where((r) => r.method == 'PUT'), hasLength(1));
    expect(find.text('Configuração salva'), findsNothing);
  });

  testWidgets('Fazer backup agora posts run-now and says when it starts', (tester) async {
    final (_, log) = await _pump(tester, _settings());
    await tester.tap(find.byKey(const ValueKey('backup-run-now')));
    await tester.pump();
    await tester.pump();
    expect(log.where((r) => r.method == 'POST' && r.url.path == '/api/admin/backup-settings/run-now'), hasLength(1));
    expect(find.text('Pedido enviado. O backup começa em instantes.'), findsOneWidget);
    expect(find.textContaining('Pedido de backup agora aguardando'), findsOneWidget);
    expect(find.text('Aguardando o programa de backup…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('backup-progress')));
    expect(bar.value, isNull);
    expect(find.text('Backup em andamento'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('backup-run-now'))).onPressed, isNull);
    int polls() => log.where((r) => r.method == 'GET' && r.url.path == '/api/admin/backup-settings').length;
    final before = polls();
    await tester.pump(const Duration(seconds: 1));
    expect(polls(), before + 1);
    await _unmount(tester);
  });

  testWidgets('shows the percentage and the stage while the backup runs, then the result', (tester) async {
    final requested = DateTime.now().toUtc().toIso8601String();
    await _pump(tester, {..._settings(), 'runRequestedAt': requested}, settle: false);
    expect(find.text('Aguardando o programa de backup…'), findsOneWidget);
    _live = {..._settings(), 'runRequestedAt': requested, 'progress': _progress(42, 'Copiando o banco')};
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('Copiando o banco'), findsOneWidget);
    expect(find.text('Aguardando o programa de backup…'), findsNothing);
    expect(tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('backup-progress'))).value, 0.42);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('backup-run-now'))).onPressed, isNull);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Progresso do backup'), findsOneWidget);

    final done = DateTime.now().toUtc().add(const Duration(seconds: 3)).toIso8601String();
    _live = {
      ..._settings(),
      'runRequestedAt': requested,
      'lastRunAt': done,
      'lastRunMessage': 'Cópia ebt-9.dump criada',
      'progress': _progress(100, null, running: false),
    };
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('backup-progress')), findsNothing);
    expect(find.text('Cópia ebt-9.dump criada'), findsWidgets);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('backup-run-now'))).onPressed, isNotNull);
    await _unmount(tester);
  });

  testWidgets('a failed run shows the failure message and keeps polling quiet on errors', (tester) async {
    final requested = DateTime.now().toUtc().toIso8601String();
    await _pump(tester, {..._settings(), 'progress': _progress(10, 'Iniciando')}, settle: false);
    expect(find.text('10%'), findsOneWidget);
    _live = {
      ..._settings(lastRunOk: false),
      'runRequestedAt': requested,
      'lastRunAt': DateTime.now().toUtc().add(const Duration(seconds: 5)).toIso8601String(),
      'lastRunMessage': 'Disco cheio',
    };
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Disco cheio'), findsWidgets);
    expect(find.byKey(const ValueKey('backup-progress')), findsNothing);
    expect(find.textContaining('Último backup falhou'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('warns when the agent stays silent for over a minute while waiting', (tester) async {
    final requested = DateTime.now().toUtc().toIso8601String();
    final seen = DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();
    await _pump(tester, {..._settings(agentSeenAt: seen), 'runRequestedAt': requested}, settle: false);
    expect(find.byKey(const ValueKey('backup-agent-warning')), findsNothing);
    for (var i = 0; i < 62; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byKey(const ValueKey('backup-agent-warning')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('polling gives up after ten minutes and the timer dies with the view', (tester) async {
    final requested = DateTime.now().toUtc().toIso8601String();
    final (_, log) = await _pump(tester, {..._settings(), 'runRequestedAt': requested}, settle: false);
    for (var i = 0; i < 610; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final gets = log.where((r) => r.method == 'GET').length;
    await tester.pump(const Duration(seconds: 9));
    // Only the slow ten-second refresh is left: at most one more call in nine seconds, not nine.
    expect(log.where((r) => r.method == 'GET').length, lessThanOrEqualTo(gets + 1));
    await _unmount(tester);
  });

  testWidgets('a poll error does not stop the polling or show a message', (tester) async {
    final requested = DateTime.now().toUtc().toIso8601String();
    await _pump(tester, {..._settings(), 'runRequestedAt': requested}, settle: false);
    _failGet = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const ValueKey('backup-progress')), findsOneWidget);
    _failGet = false;
    _live = {..._settings(), 'runRequestedAt': requested, 'progress': _progress(7, null)};
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('7%'), findsOneWidget);
    await _unmount(tester);
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

  testWidgets('a view left open notices the agent and the finished backup on its own', (tester) async {
    final (_, log) = await _pump(tester, _settings(agentSeenAt: null)..['lastRunAt'] = null);
    expect(find.byKey(const ValueKey('backup-agent-warning')), findsOneWidget);
    expect(find.text('Nenhum backup automático executado ainda'), findsOneWidget);
    _live = _settings();
    final before = log.where((r) => r.method == 'GET').length;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(log.where((r) => r.method == 'GET').length, before + 1);
    expect(find.byKey(const ValueKey('backup-agent-warning')), findsNothing);
    expect(find.textContaining('Último backup deu certo'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a silent reload keeps unsaved edits but updates the status', (tester) async {
    await _pump(tester, _settings());
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '2');
    _live = {..._settings(), 'keep': 5, 'lastRunMessage': 'Cópia nova'};
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('Cópia nova'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('5'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a silent reload refreshes a clean form', (tester) async {
    await _pump(tester, _settings());
    _live = {..._settings(), 'keep': 4};
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the refresh button reloads at once', (tester) async {
    final (_, log) = await _pump(tester, _settings(agentSeenAt: null));
    expect(find.byTooltip('Atualizar'), findsOneWidget);
    _live = _settings();
    final before = log.where((r) => r.method == 'GET').length;
    await tester.tap(find.byKey(const ValueKey('backup-refresh')));
    await tester.pump();
    await tester.pump();
    expect(log.where((r) => r.method == 'GET').length, before + 1);
    expect(find.byKey(const ValueKey('backup-agent-warning')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a failing reload keeps the old state and shows no message', (tester) async {
    await _pump(tester, _settings(agentSeenAt: null));
    _failGet = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('backup-refresh')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const ValueKey('backup-agent-warning')), findsOneWidget);
    expect(find.textContaining('Último backup deu certo'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a reload that finds a waiting request switches to fast polling, and timers die with the view', (tester) async {
    final (_, log) = await _pump(tester, _settings());
    _live = {..._settings(), 'runRequestedAt': DateTime.now().toUtc().toIso8601String()};
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('Aguardando o programa de backup…'), findsOneWidget);
    final before = log.where((r) => r.method == 'GET').length;
    await tester.pump(const Duration(seconds: 1));
    expect(log.where((r) => r.method == 'GET').length, before + 1);
    await _unmount(tester);
    final after = log.length;
    await tester.pump(const Duration(seconds: 30));
    expect(log.length, after);
  });

  testWidgets('Fazer backup agora saves a dirty form first, then requests the run', (tester) async {
    final (_, log) = await _pump(tester, _settings());
    await tester.enterText(find.byKey(const ValueKey('backup-destination')), r'E:\copias');
    await tester.tap(find.byKey(const ValueKey('backup-run-now')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final writes = log.where((r) => r.method != 'GET' && r.url.path.startsWith('/api/admin/backup-settings')).toList();
    expect(writes.map((r) => r.method), ['PUT', 'POST']);
    expect(writes[1].url.path, endsWith('/run-now'));
    expect((jsonDecode(writes[0].body) as Map)['destination'], r'E:\copias');
    expect(find.text('Alterações salvas. Pedido enviado. O backup começa em instantes.'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('an invalid form blocks Fazer backup agora', (tester) async {
    final (_, log) = await _pump(tester, _settings());
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '0');
    await tester.tap(find.byKey(const ValueKey('backup-run-now')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Informe de 1 a 5.'), findsOneWidget);
    expect(log.where((r) => r.method != 'GET' && r.url.path.startsWith('/api/admin/backup-settings')), isEmpty);
  });

  testWidgets('a failed save does not request the run', (tester) async {
    final (_, log) = await _pump(tester, _settings(), putStatus: 400);
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '4');
    await tester.tap(find.byKey(const ValueKey('backup-run-now')));
    await tester.pump();
    await tester.pump();
    expect(log.where((r) => r.method == 'PUT'), hasLength(1));
    expect(log.where((r) => r.url.path.endsWith('/run-now')), isEmpty);
  });

  testWidgets('picking a folder on a clean form saves it at once and opens the picker at the last folder', (tester) async {
    String? seen = 'unset';
    final (_, log) = await _pump(
      tester,
      _settings(destination: r'D:\backups'),
      home: (s) => BackupSettingsView(
        session: s,
        canBrowse: true,
        pickFolder: (d) async {
          seen = d;
          return r'E:\copias';
        },
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('backup-pick-folder')));
    expect(seen, r'D:\backups');
    final put = log.singleWhere((r) => r.method == 'PUT');
    expect((jsonDecode(put.body) as Map)['destination'], r'E:\copias');
    expect(find.text('Pasta de destino salva.'), findsOneWidget);
    expect(find.text(r'E:\copias'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('backup-pick-folder')));
    expect(seen, r'E:\copias');
  });

  testWidgets('picking a folder on a dirty form only fills the field', (tester) async {
    final (_, log) = await _pump(
      tester,
      _settings(),
      home: (s) => BackupSettingsView(session: s, canBrowse: true, pickFolder: (_) async => r'E:\copias'),
    );
    await tester.enterText(find.byKey(const ValueKey('backup-keep')), '2');
    await _tap(tester, find.byKey(const ValueKey('backup-pick-folder')));
    expect(log.where((r) => r.method == 'PUT'), isEmpty);
    expect(find.text(r'E:\copias'), findsOneWidget);
  });

  testWidgets('folder picker button is hidden on the test platform and shown when forced', (tester) async {
    await _pump(tester, _settings());
    expect(find.byKey(const ValueKey('backup-pick-folder')), findsNothing);
    expect(find.textContaining('precisa existir no computador do servidor'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _settings(), home: (s) => BackupSettingsView(session: s, canBrowse: true));
    expect(find.byKey(const ValueKey('backup-pick-folder')), findsOneWidget);
    expect(find.byTooltip('Procurar pasta'), findsOneWidget);
    expect(find.textContaining('precisa existir no computador do servidor'), findsOneWidget);
  });

  testWidgets('picked folder fills the field and is saved; cancelled picker changes nothing', (tester) async {
    var answer = r'E:\copias';
    final (_, log) = await _pump(
      tester,
      _settings(destination: r'D:\backups'),
      home: (s) => BackupSettingsView(session: s, canBrowse: true, pickFolder: (_) async => answer.isEmpty ? null : answer),
    );
    answer = '';
    await _tap(tester, find.byKey(const ValueKey('backup-pick-folder')));
    expect(find.text(r'D:\backups'), findsOneWidget);
    answer = r'E:\copias';
    await _tap(tester, find.byKey(const ValueKey('backup-pick-folder')));
    expect(find.text(r'E:\copias'), findsOneWidget);
    final body = jsonDecode(log.singleWhere((r) => r.method == 'PUT').body) as Map<String, dynamic>;
    expect(body['destination'], r'E:\copias');
  });

  testWidgets('a picker failure is shown as a friendly message', (tester) async {
    await _pump(
      tester,
      _settings(),
      home: (s) => BackupSettingsView(session: s, canBrowse: true, pickFolder: (_) async => throw StateError('boom')),
    );
    await _tap(tester, find.byKey(const ValueKey('backup-pick-folder')));
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });
  group('Interromper', () {
    Map<String, dynamic> running() => {
      ..._settings(),
      'runRequestedAt': DateTime.now().toUtc().toIso8601String(),
      'progress': _progress(30, 'Copiando o banco'),
    };

    Finder cancelBtn() => find.byKey(const ValueKey('backup-cancel'));
    int cancels(List<http.Request> log) => log.where((r) => r.method == 'POST' && r.url.path.endsWith('/backup-settings/cancel')).length;

    testWidgets('is shown while waiting and while running, hidden when idle', (tester) async {
      await _pump(tester, _settings());
      expect(cancelBtn(), findsNothing);
      await _unmount(tester);
      await _pump(tester, {..._settings(), 'runRequestedAt': DateTime.now().toUtc().toIso8601String()}, settle: false);
      expect(cancelBtn(), findsOneWidget);
      expect(find.text('Interromper'), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      await _unmount(tester);
      await _pump(tester, running(), settle: false);
      expect(cancelBtn(), findsOneWidget);
      expect(tester.widget<OutlinedButton>(cancelBtn()).onPressed, isNotNull);
      await _unmount(tester);
    });

    testWidgets('Continuar in the dialog does not post', (tester) async {
      final (_, log) = await _pump(tester, running(), settle: false);
      await tester.tap(cancelBtn());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Interromper o backup?'), findsOneWidget);
      expect(find.text('O backup em andamento será cancelado e o arquivo parcial descartado.'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Interromper o backup?'), findsNothing);
      expect(cancels(log), 0);
      await _unmount(tester);
    });

    testWidgets('confirming posts once, tells it, and disables the button', (tester) async {
      final (_, log) = await _pump(tester, running(), settle: false);
      await tester.tap(cancelBtn());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Interromper')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(cancels(log), 1);
      expect(find.text('Interrompendo o backup...'), findsOneWidget);
      expect(find.text('Interrompendo...'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(cancelBtn()).onPressed, isNull);
      // polling keeps going while the agent stops the run
      final before = log.where((r) => r.method == 'GET').length;
      await tester.pump(const Duration(seconds: 1));
      expect(log.where((r) => r.method == 'GET').length, before + 1);
      expect(cancels(log), 1);
      await _unmount(tester);
    });

    testWidgets('a finished cancellation shows the neutral snackbar and the neutral last-run block', (tester) async {
      await _pump(tester, running(), settle: false);
      _live = {
        ..._settings(lastRunOk: false),
        'lastRunAt': DateTime.now().toUtc().add(const Duration(seconds: 5)).toIso8601String(),
        'lastRunMessage': 'Backup cancelado.',
        'progress': _progress(0, 'Cancelado', running: false),
      };
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect((bar.content as Text).data, 'Backup interrompido.');
      expect(bar.backgroundColor, isNull);
      expect(find.textContaining('Interrompido em'), findsOneWidget);
      expect(find.textContaining('Último backup falhou'), findsNothing);
      expect(cancelBtn(), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a stale cancel request from an earlier run does not disable the button', (tester) async {
      final started = DateTime.now().toUtc().toIso8601String();
      final old = DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String();
      await _pump(tester, {
        ...running(),
        'cancelRequestedAt': old,
        'progress': {..._progress(30, 'Copiando o banco'), 'startedAt': started},
      }, settle: false);
      expect(tester.widget<OutlinedButton>(cancelBtn()).onPressed, isNotNull);
      expect(find.text('Interromper'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a failed post shows the error and keeps the button', (tester) async {
      final (_, log) = await _pump(tester, running(), settle: false);
      _failCancel = true;
      await tester.tap(cancelBtn());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Interromper')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(cancels(log), 1);
      expect(find.text('Interrompendo o backup...'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Interromper'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(cancelBtn()).onPressed, isNotNull);
      await _unmount(tester);
    });
  });

  group('pasta de destino obrigatória', () {
    const hint = 'Escolha a pasta de destino para poder fazer o backup.';
    Finder runNow() => find.byKey(const ValueKey('backup-run-now'));
    Finder dest() => find.byKey(const ValueKey('backup-destination'));

    testWidgets('Fazer backup agora is disabled without a destination and enables when one is typed', (tester) async {
      await _pump(tester, _settings(destination: null, enabled: false));
      expect(tester.widget<OutlinedButton>(runNow()).onPressed, isNull);
      expect(find.text(hint), findsOneWidget);
      expect(find.byTooltip(hint), findsOneWidget);
      expect(find.text('Pasta de destino da cópia (obrigatória)'), findsOneWidget);
      await tester.enterText(dest(), '   ');
      await tester.pump();
      expect(tester.widget<OutlinedButton>(runNow()).onPressed, isNull);
      await tester.enterText(dest(), r'E:\copias');
      await tester.pump();
      expect(tester.widget<OutlinedButton>(runNow()).onPressed, isNotNull);
      expect(find.text(hint), findsNothing);
      expect(find.text('Pasta de destino da cópia'), findsOneWidget);
    });

    testWidgets('picking a folder enables Fazer backup agora', (tester) async {
      await _pump(
        tester,
        _settings(destination: null, enabled: false),
        home: (s) => BackupSettingsView(session: s, canBrowse: true, pickFolder: (_) async => r'E:\copias'),
      );
      expect(tester.widget<OutlinedButton>(runNow()).onPressed, isNull);
      await _tap(tester, find.byKey(const ValueKey('backup-pick-folder')));
      expect(tester.widget<OutlinedButton>(runNow()).onPressed, isNotNull);
    });

    testWidgets('the automatic switch refuses to turn on without a destination', (tester) async {
      await _pump(tester, _settings(destination: null, enabled: false));
      await _tap(tester, find.byKey(const ValueKey('backup-enabled')));
      expect(find.text('Escolha a pasta de destino antes de ligar o backup automático.'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('backup-enabled'))).value, isFalse);
      await tester.enterText(dest(), r'E:\copias');
      await tester.pump();
      await _tap(tester, find.byKey(const ValueKey('backup-enabled')));
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('backup-enabled'))).value, isTrue);
    });

    testWidgets('Salvar with the switch on and the destination cleared shows the field error and does not PUT', (tester) async {
      final (_, log) = await _pump(tester, _settings());
      await tester.enterText(dest(), '');
      await _tap(tester, find.byKey(const ValueKey('backup-save')));
      expect(find.text('Informe a pasta de destino.'), findsOneWidget);
      expect(log.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(dest(), r'E:\copias');
      await tester.pumpAndSettle();
      expect(find.text('Informe a pasta de destino.'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('backup-save')));
      expect(log.where((r) => r.method == 'PUT'), hasLength(1));
    });

    testWidgets('turning the switch off clears the error and saves without destination', (tester) async {
      final (_, log) = await _pump(tester, _settings());
      await tester.enterText(dest(), '');
      await _tap(tester, find.byKey(const ValueKey('backup-save')));
      await _tap(tester, find.byKey(const ValueKey('backup-enabled')));
      expect(find.text('Informe a pasta de destino.'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('backup-save')));
      final body = jsonDecode(log.singleWhere((r) => r.method == 'PUT').body) as Map<String, dynamic>;
      expect(body['enabled'], isFalse);
      expect(body['destination'], isNull);
    });

    testWidgets('a 400 destination error from the server is shown through the normal error path', (tester) async {
      final (_, log) = await _pump(tester, _settings(), putStatus: 400, putErrorField: 'destination');
      await tester.enterText(dest(), r'E:\copias');
      await _tap(tester, find.byKey(const ValueKey('backup-save')));
      expect(log.where((r) => r.method == 'PUT'), hasLength(1));
      expect(find.textContaining('Informe a pasta de destino.'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  testWidgets('Backup section shows the status and the form', (tester) async {
    await _pump(tester, _settings(), home: (s) => BackupSection(session: s));
    expect(find.byKey(const ValueKey('settings-backup')), findsOneWidget);
    expect(find.byType(BackupSettingsView), findsOneWidget);
  });
}

void drillTests() {
  test('DrillInfo reads the last restore drill from /health/ready', () {
    expect(DrillInfo.from({'backup': {}}), isNull);
    expect(DrillInfo.from('x'), isNull);
    final ok = DrillInfo.from({'backup': {'drill': {'ok': true, 'at': '2026-11-01T10:00:00Z'}}})!;
    expect(ok.ok, isTrue);
    expect(ok.at, isNotNull);
    expect(DrillInfo.from({'backup': {'drill': {'ok': false}}})!.ok, isFalse);
  });
}
