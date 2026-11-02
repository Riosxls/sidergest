import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/settings/settings_backup.dart';
import 'package:ebt_engenharia/screens/settings/settings_restore.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

Map<String, dynamic> _item(String name, {String location = 'local', bool checksum = true, Duration age = const Duration(hours: 3)}) => {
  'name': name,
  'sizeBytes': 5 * 1048576,
  'createdAt': _ago(age),
  'location': location,
  'hasChecksum': checksum,
};

/// Server state the fake API answers from; a test mutates it between ticks.
class _Server {
  List<Map<String, dynamic>> items = [
    _item('ebt-2.dump', location: 'both'),
    _item('ebt-1.dump', checksum: false, age: const Duration(days: 1)),
  ];
  Map<String, dynamic> restore = {'requestedAt': null, 'file': null, 'result': null};
  Map<String, dynamic>? progress;
  bool down = false;
  int unauthorized = 0;
  int postStatus = 202;
  String? postError;
  final log = <http.Request>[];

  Map<String, dynamic> get catalog => {'items': items, 'listedAt': _ago(Duration.zero), 'restore': restore};

  void request() => restore = {'requestedAt': _ago(const Duration(seconds: 5)), 'file': 'ebt-2.dump', 'result': null};

  void finish({required bool ok, String? message}) => restore = {
    ...restore,
    'result': {'ok': ok, 'message': message, 'file': 'ebt-2.dump', 'safetyDump': ok ? 'ebt-seguranca.dump' : null, 'finishedAt': _ago(Duration.zero)},
  };

  Map<String, dynamic> get settings => {
    'enabled': true,
    'frequency': 'Daily',
    'timeOfDay': '22:00',
    'weekday': 1,
    'destination': r'D:\backups',
    'keep': 14,
    'runRequestedAt': null,
    'lastRunAt': _ago(const Duration(hours: 3)),
    'lastRunOk': true,
    'lastRunMessage': 'Cópia criada',
    'agentSeenAt': _ago(const Duration(minutes: 1)),
    'nextRunAt': DateTime.now().toUtc().add(const Duration(hours: 5)).toIso8601String(),
    'progress': progress,
  };
}

Future<(Session, _Server)> _pump(WidgetTester tester, _Server s) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = MockClient((r) async {
    s.log.add(r);
    if (s.down) throw http.ClientException('connection refused');
    if (s.unauthorized > 0 && r.url.path.startsWith('/api/admin/backups')) {
      s.unauthorized--;
      return _json({'title': 'x'}, 401);
    }
    switch (r.url.path) {
      case '/api/admin/backups':
        return _json(s.catalog);
      case '/api/admin/backups/restore':
        if (s.postStatus != 202) {
          return _json({
            'title': s.postError,
            'errors': {
              'confirm': ['Valor inválido'],
            },
          }, s.postStatus);
        }
        s.request();
        return _json(s.catalog, 202);
      case '/api/admin/backups/restore/cancel':
        s.restore = {'requestedAt': null, 'file': null, 'result': null};
        return _json(s.catalog);
      case '/api/admin/backup-settings':
        return _json(s.settings);
    }
    return _json({'configured': false, 'count': 0});
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
        body: SingleChildScrollView(child: BackupSettingsView(session: session)),
      ),
    ),
  );
  await _settle(tester);
  return (session, s);
}

/// Like pumpAndSettle, but the indeterminate progress bar animates forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// One 2 s poll of the restore screen.
Future<void> _poll(WidgetTester tester) async {
  await tester.pump(restorePollInterval);
  await tester.pump();
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _settle(tester);
  await tester.tap(f);
  await _settle(tester);
}

Future<void> _openDialog(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('restore-item-ebt-2.dump')));
  await _tap(tester, find.byKey(const ValueKey('restore-start')));
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('restore-confirm')), 'RESTAURAR');
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('restore-confirm-run')));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('lists the backups and selecting one enables the restore button', (tester) async {
    await _pump(tester, _Server());
    expect(find.byKey(const ValueKey('restore-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-item-ebt-2.dump')), findsOneWidget);
    expect(find.text('Nos dois'), findsOneWidget);
    expect(find.text('Neste computador'), findsOneWidget);
    expect(find.textContaining('5.0 MB'), findsNWidgets(2));
    expect(find.text('Sem verificação'), findsOneWidget);
    FilledButton button() => tester.widget<FilledButton>(find.byKey(const ValueKey('restore-start')));
    expect(button().onPressed, isNull);
    await _tap(tester, find.byKey(const ValueKey('restore-item-ebt-1.dump')));
    expect(button().onPressed, isNotNull);
    await _unmount(tester);
  });

  testWidgets('shows the empty state', (tester) async {
    await _pump(tester, _Server()..items = []);
    expect(find.text('Nenhum backup encontrado. Faça um backup primeiro.'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('restore is blocked while a backup runs', (tester) async {
    await _pump(tester, _Server()..progress = {'running': true, 'percent': 20, 'stage': 'Copiando', 'startedAt': null, 'updatedAt': null});
    await _tap(tester, find.byKey(const ValueKey('restore-item-ebt-2.dump')));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('restore-start'))).onPressed, isNull);
    await _unmount(tester);
  });

  testWidgets('the dialog needs the exact word and posts file and confirm', (tester) async {
    final s = _Server();
    await _pump(tester, s);
    await _openDialog(tester);
    expect(find.byKey(const ValueKey('restore-dialog')), findsOneWidget);
    expect(find.textContaining('Isto substitui TODOS os dados atuais'), findsOneWidget);
    FilledButton run() => tester.widget<FilledButton>(find.byKey(const ValueKey('restore-confirm-run')));
    expect(run().onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('restore-confirm')), 'restaurar');
    await tester.pump();
    expect(run().onPressed, isNull);
    await _confirm(tester);
    final post = s.log.lastWhere((r) => r.method == 'POST');
    expect(post.url.path, '/api/admin/backups/restore');
    expect(jsonDecode(post.body), {'file': 'ebt-2.dump', 'confirm': 'RESTAURAR'});
    expect(find.byKey(const ValueKey('restore-running')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a 409 stays in the dialog', (tester) async {
    final s = _Server()
      ..postStatus = 409
      ..postError = 'Já existe uma restauração pendente';
    await _pump(tester, s);
    await _openDialog(tester);
    await _confirm(tester);
    expect(find.byKey(const ValueKey('restore-dialog-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-running')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('running shows the stage, then the restart phase, then success logs out', (tester) async {
    final s = _Server();
    final (session, _) = await _pump(tester, s);
    await _openDialog(tester);
    await _confirm(tester);
    s.progress = {'running': true, 'percent': 40, 'stage': 'Restaurando o banco', 'startedAt': null, 'updatedAt': null};
    await _poll(tester);
    expect(find.text('Restaurando o banco'), findsOneWidget);
    expect(find.byKey(const ValueKey('restore-cancel')), findsNothing);

    s.down = true;
    await _poll(tester);
    expect(find.text('O sistema está reiniciando…'), findsOneWidget);
    expect(find.textContaining('Tempo decorrido: 00:04'), findsOneWidget);
    await _poll(tester);
    expect(find.textContaining('Tempo decorrido: 00:06'), findsOneWidget);

    s.down = false;
    s.progress = null;
    s.finish(ok: true);
    await _poll(tester);
    await _settle(tester);
    expect(find.textContaining('Backup restaurado. Entre de novo.'), findsOneWidget);
    expect(find.textContaining('ebt-seguranca.dump'), findsOneWidget);
    expect(session.username, 'ana');
    await tester.tap(find.text('OK'));
    await _settle(tester);
    expect(session.username, isNull);
    await _unmount(tester);
  });

  testWidgets('a failed restore says so and returns to the normal view', (tester) async {
    final s = _Server();
    final (session, _) = await _pump(tester, s);
    await _openDialog(tester);
    await _confirm(tester);
    s.finish(ok: false, message: 'arquivo corrompido');
    await _poll(tester);
    await _settle(tester);
    expect(find.textContaining('A restauração falhou: arquivo corrompido. Os dados atuais foram mantidos.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('restore-running')), findsNothing);
    expect(find.byKey(const ValueKey('restore-list')), findsOneWidget);
    expect(find.text('Backup automático'), findsOneWidget);
    expect(session.username, 'ana');
    await _unmount(tester);
  });

  testWidgets('a lost login while polling is treated as the new database', (tester) async {
    final s = _Server();
    final (session, _) = await _pump(tester, s);
    await _openDialog(tester);
    await _confirm(tester);
    s.unauthorized = 1;
    await _poll(tester);
    await _settle(tester);
    expect(find.textContaining('Backup restaurado. Entre de novo.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    expect(session.username, isNull);
    await _unmount(tester);
  });

  testWidgets('the database coming back without a request counts as restored', (tester) async {
    final s = _Server();
    await _pump(tester, s);
    await _openDialog(tester);
    await _confirm(tester);
    s.down = true;
    await _poll(tester);
    s.down = false;
    s.restore = {'requestedAt': null, 'file': null, 'result': null};
    await _poll(tester);
    await _settle(tester);
    expect(find.textContaining('Backup restaurado. Entre de novo.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    await _unmount(tester);
  });

  testWidgets('opening in the middle of a restore goes straight to the running view and the pending request can be cancelled', (tester) async {
    final s = _Server()..request();
    await _pump(tester, s);
    expect(find.byKey(const ValueKey('restore-running')), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-save')), findsNothing);
    await _poll(tester);
    await tester.tap(find.byKey(const ValueKey('restore-cancel')));
    await _settle(tester);
    expect(s.log.any((r) => r.url.path == '/api/admin/backups/restore/cancel'), isTrue);
    expect(find.byKey(const ValueKey('restore-running')), findsNothing);
    expect(find.byKey(const ValueKey('restore-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-save')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('gives up after fifteen minutes and can check again', (tester) async {
    final s = _Server()..request();
    await _pump(tester, s);
    s.down = true;
    await tester.pump(restoreGiveUpAfter + const Duration(seconds: 4));
    await tester.pump();
    expect(find.textContaining('demorando mais do que o esperado'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore-recheck')));
    await tester.pump();
    expect(find.textContaining('demorando mais do que o esperado'), findsNothing);
    await _unmount(tester);
  });
}
