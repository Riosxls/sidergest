import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart' show appTheme;
import 'package:ebt_engenharia/prefs.dart';
import 'package:ebt_engenharia/screens/settings/settings_dialog.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/idle_guard.dart';
import 'package:ebt_engenharia/widgets/print_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _login(String token) => {
  'token': token,
  'username': 'ana',
  'role': 'Admin',
  'permissions': ['read', 'admin'],
  'expiresAt': DateTime.now().add(const Duration(minutes: 60)).toUtc().toIso8601String(),
  'refreshToken': 'r-$token',
  'refreshExpiresAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
};

/// Opens the settings dialog for [role]; [handler] answers the API calls. Returns the session and the request log.
Future<(Session, List<http.Request>)> open(WidgetTester tester, String role, Future<http.Response> Function(http.Request) handler, {String? section}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    return handler(r);
  });
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok')..refreshToken = 'r-mine')
    ..username = 'ana'
    ..role = role
    ..permissions = rolePermissions[role]!;
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (c) => Scaffold(body: TextButton(onPressed: () => showUserSettings(c, session, section: section), child: const Text('abrir'))),
      ),
    ),
  );
  await tapV(tester, find.text('abrir'));
  await tester.pumpAndSettle();
  return (session, log);
}

Future<void> goTo(WidgetTester tester, String section) async {
  await tapV(tester, find.byKey(ValueKey('settings-nav-$section')));
  await tester.pumpAndSettle();
}

Future<http.Response> none(http.Request r) async => json({'title': 'x', 'status': 500}, 500);

void main() {
  setUp(() {
    AppPrefs.rowsPerPage = 50;
    AppPrefs.printPrompts = true;
  });

  group('frame', () {
    testWidgets('lists the sections; Administração is only for admins', (tester) async {
      await open(tester, 'Reader', none);
      for (final id in ['appearance', 'general', 'print', 'account', 'data', 'about']) {
        expect(find.byKey(ValueKey('settings-nav-$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const ValueKey('settings-nav-admin')), findsNothing);
      await tapV(tester, find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      await open(tester, 'Admin', none);
      expect(find.byKey(const ValueKey('settings-nav-admin')), findsOneWidget);
    });

    testWidgets('a requested section opens first and a sub-view has a back arrow', (tester) async {
      await open(tester, 'SalesManager', (r) async => json([]), section: 'general');
      expect(find.text('Tela inicial'), findsOneWidget);
      await tapV(tester, find.text('Atalhos de teclado'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-sub-back')), findsOneWidget);
      expect(find.text('Ctrl + K'), findsOneWidget);
      await tapV(tester, find.byKey(const ValueKey('settings-sub-back')));
      await tester.pumpAndSettle();
      expect(find.text('Tela inicial'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-sub-back')), findsNothing);
    });

    testWidgets('on a narrow window the sections are a menu first', (tester) async {
      await open(tester, 'Reader', none);
      tester.view.physicalSize = const Size(500, 900);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-nav-about')), findsOneWidget);
      await goTo(tester, 'print');
      expect(find.byKey(const ValueKey('settings-print-prompts')), findsOneWidget);
      await tapV(tester, find.byKey(const ValueKey('settings-back-to-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-nav-print')), findsOneWidget);
    });
  });

  group('preferences', () {
    testWidgets('Aparência: contrast and reduced motion are saved', (tester) async {
      final (s, _) = await open(tester, 'Reader', none);
      await tapV(tester, find.byKey(const ValueKey('settings-contrast')));
      await tapV(tester, find.byKey(const ValueKey('settings-motion')));
      await tester.pumpAndSettle();
      expect(s.highContrast, isTrue);
      expect(s.reduceMotion, isTrue);
      final again = Session();
      await again.restore();
      expect(again.highContrast, isTrue);
      expect(again.reduceMotion, isTrue);
      expect(appTheme(Brightness.light, highContrast: true).colorScheme.primary, isNot(appTheme(Brightness.light).colorScheme.primary));
    });

    testWidgets('Geral: refresh interval and rows per page change the session and the list default', (tester) async {
      final (s, _) = await open(tester, 'Reader', none);
      await goTo(tester, 'general');
      await tapV(tester, find.descendant(of: find.byKey(const ValueKey('settings-refresh')), matching: find.text('5 min')));
      await tapV(tester, find.descendant(of: find.byKey(const ValueKey('settings-rows')), matching: find.text('100')));
      await tester.pumpAndSettle();
      expect(s.dashboardRefreshMinutes, 5);
      expect(s.rowsPerPage, 100);
      expect(AppPrefs.rowsPerPage, 100);
      final again = Session();
      await again.restore();
      expect(again.dashboardRefreshMinutes, 5);
      expect(AppPrefs.rowsPerPage, 100);
    });

    test('invalid saved values fall back to the defaults', () async {
      SharedPreferences.setMockInitialValues({'rowsPerPage': 7, 'dashboardRefreshMinutes': 3, 'idleLockMinutes': 1});
      final s = Session();
      await s.restore();
      expect(s.rowsPerPage, 50);
      expect(s.dashboardRefreshMinutes, 2);
      expect(s.idleLockMinutes, 0);
    });

    testWidgets('Geral: the home screen choice is saved', (tester) async {
      final (s, _) = await open(tester, 'Reader', none);
      await goTo(tester, 'general');
      await s.setHomeScreen('customers');
      final again = Session();
      await again.restore();
      expect(again.homeScreen, 'customers');
    });
  });

  group('impressão', () {
    testWidgets('turning prompts off lets printGate pass without asking', (tester) async {
      final (s, _) = await open(tester, 'Reader', none);
      await goTo(tester, 'print');
      await tapV(tester, find.byKey(const ValueKey('settings-print-prompts')));
      await tester.pumpAndSettle();
      expect(s.printPrompts, isFalse);
      expect(AppPrefs.printPrompts, isFalse);
      late bool passed;
      await tapV(tester, find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async => passed = await printGate(c, doneKey: 'k', title: 't', message: 'm', onPrint: () async {}),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tapV(tester, find.text('go'));
      await tester.pumpAndSettle();
      expect(passed, isTrue);
      expect(find.byKey(const ValueKey('gate-print')), findsNothing);
    });

    testWidgets('forgetting the history makes the gate ask again', (tester) async {
      await open(tester, 'Reader', none);
      await PrintLog.mark('quote:1:po');
      await PrintLog.mark('order:2:of');
      await goTo(tester, 'print');
      expect(find.text('2 papéis já impressos, baixados ou ignorados.'), findsOneWidget);
      await tapV(tester, find.byKey(const ValueKey('settings-print-forget')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum papel registrado ainda.'), findsOneWidget);
      expect(await PrintLog.isDone('quote:1:po'), isFalse);
    });
  });

  group('conta', () {
    testWidgets('profile: save is off until something changes, then sends both fields', (tester) async {
      final (s, log) = await open(tester, 'Reader', (r) async {
        if (r.method == 'PUT' && r.url.path == '/api/auth/profile') return json({'username': 'ana', 'displayName': 'Ana Souza', 'email': 'ana@ebt.com.br'});
        return json({});
      }, section: 'account');
      FilledButton save() => tester.widget<FilledButton>(find.byKey(const ValueKey('settings-profile-save')));
      expect(save().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('settings-profile-name')), 'Ana Souza');
      await tester.enterText(find.byKey(const ValueKey('settings-profile-email')), 'ana@ebt.com.br');
      await tester.pump();
      expect(save().onPressed, isNotNull);
      await tapV(tester, find.byKey(const ValueKey('settings-profile-save')));
      await tester.pumpAndSettle();
      expect(jsonDecode(log.singleWhere((r) => r.method == 'PUT').body), {'displayName': 'Ana Souza', 'email': 'ana@ebt.com.br'});
      expect(s.displayName, 'Ana Souza');
      expect(s.shownName, 'Ana Souza');
    });

    testWidgets('profile: a server validation error is shown and nothing changes', (tester) async {
      final (s, _) = await open(tester, 'Reader', (r) async => json({'errors': {'email': ['Invalid email']}}, 400), section: 'account');
      await tester.enterText(find.byKey(const ValueKey('settings-profile-email')), 'sem-arroba');
      await tester.pump();
      await tapV(tester, find.byKey(const ValueKey('settings-profile-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid email'), findsOneWidget);
      expect(s.email, isNull);
    });

    testWidgets('idle lock choice is saved', (tester) async {
      final (s, _) = await open(tester, 'Reader', none, section: 'account');
      await tapV(tester, find.descendant(of: find.byKey(const ValueKey('settings-idle')), matching: find.text('30 min')));
      await tester.pumpAndSettle();
      expect(s.idleLockMinutes, 30);
    });

    testWidgets('sign out closes the window and ends the session', (tester) async {
      final (s, _) = await open(tester, 'Reader', none, section: 'account');
      await tapV(tester, find.text('Sair deste dispositivo'));
      await tester.pumpAndSettle();
      expect(s.api.token, isNull);
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('dispositivos', () {
    List<Map<String, dynamic>> devices() => [
      {'id': 1, 'device': 'Windows', 'ip': '10.0.0.5', 'createdAt': '2026-11-01T10:00:00Z', 'expiresAt': '2026-11-15T10:00:00Z', 'current': true},
      {'id': 2, 'device': 'Android', 'ip': '10.0.0.9', 'createdAt': '2026-10-30T10:00:00Z', 'expiresAt': '2026-11-13T10:00:00Z', 'current': false},
      {'id': 3, 'device': null, 'createdAt': '2026-10-29T10:00:00Z', 'expiresAt': '2026-11-12T10:00:00Z', 'current': false},
    ];

    Future<(Session, List<http.Request>)> devicesScreen(WidgetTester tester, Future<http.Response?> Function(http.Request) extra) async {
      final r = await open(tester, 'Reader', (r) async {
        final e = await extra(r);
        if (e != null) return e;
        if (r.method == 'POST' && r.url.path == '/api/auth/sessions') return json(devices());
        return json({}, 204);
      }, section: 'account');
      await tapV(tester, find.byKey(const ValueKey('settings-open-devices')));
      await tester.pumpAndSettle();
      return r;
    }

    testWidgets('lists sessions, marks this device and sends the refresh token', (tester) async {
      final (_, log) = await devicesScreen(tester, (r) async => null);
      expect(find.text('Este dispositivo'), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('Dispositivo sem nome'), findsOneWidget);
      expect(find.byKey(const ValueKey('device-disconnect-1')), findsNothing, reason: 'the current device is not disconnected from here');
      expect(jsonDecode(log.firstWhere((r) => r.url.path == '/api/auth/sessions').body), {'refreshToken': 'r-mine'});
    });

    testWidgets('disconnecting one device deletes only that session', (tester) async {
      final (_, log) = await devicesScreen(tester, (r) async => null);
      await tapV(tester, find.byKey(const ValueKey('device-disconnect-2')));
      await tester.pumpAndSettle();
      final del = log.singleWhere((r) => r.method == 'DELETE');
      expect(del.url.path, '/api/auth/sessions/2');
      expect(find.text('Dispositivo desconectado'), findsOneWidget);
    });

    testWidgets('disconnect others asks first, then swaps in the new tokens', (tester) async {
      final (s, log) = await devicesScreen(tester, (r) async => r.url.path == '/api/auth/sessions/revoke-others' ? json(_login('fresh')) : null);
      await tapV(tester, find.byKey(const ValueKey('devices-revoke-others')));
      await tester.pumpAndSettle();
      expect(log.where((r) => r.url.path.endsWith('revoke-others')), isEmpty, reason: 'nothing is sent before the confirmation');
      await tapV(tester, find.byKey(const ValueKey('devices-confirm-others')));
      await tester.pumpAndSettle();
      expect(jsonDecode(log.singleWhere((r) => r.url.path.endsWith('revoke-others')).body), {'refreshToken': 'r-mine'});
      expect(s.api.token, 'fresh');
    });

    testWidgets('a load failure shows the error with a retry button', (tester) async {
      await open(tester, 'Reader', (r) async => json({'title': 'Registro bloqueado', 'status': 409}, 409), section: 'account');
      await tapV(tester, find.byKey(const ValueKey('settings-open-devices')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Registro bloqueado'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });
  });

  group('sobre', () {
    testWidgets('shows app and server facts', (tester) async {
      await open(tester, 'Reader', (r) async {
        if (r.url.path == '/api/system/about') {
          return json({'version': '1.4.2', 'runtime': '.NET 10.0.14', 'environment': 'Production', 'serverTime': '2026-11-01T12:00:00Z', 'timeZone': 'America/Sao_Paulo', 'lastMigration': '20261101_SessionDevices', 'databaseOk': true});
        }
        return json({});
      }, section: 'about');
      expect(find.text('1.4.2'), findsOneWidget);
      expect(find.text('20261101_SessionDevices'), findsOneWidget);
      expect(find.text('Conectado'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-copy-diagnostics')), findsOneWidget);
    });

    testWidgets('offline server is said plainly and the diagnostic still works', (tester) async {
      await open(tester, 'Reader', none, section: 'about');
      expect(find.byKey(const ValueKey('settings-about-offline')), findsOneWidget);
    });
  });

  group('administração', () {
    Future<http.Response> backup(Map<String, dynamic> body) async => json(body);

    testWidgets('backup: recent, old, missing and unconfigured', (tester) async {
      final recent = DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String();
      await open(tester, 'Admin', (r) => backup({'configured': true, 'count': 14, 'lastBackupAt': recent, 'lastBackupFile': 'ebt-nightly-1.dump', 'lastBackupSizeBytes': 5242880}), section: 'admin');
      expect(find.text('Backup em dia'), findsOneWidget);
      expect(find.text('ebt-nightly-1.dump'), findsOneWidget);
      expect(find.textContaining('14 arquivos'), findsOneWidget);
    });

    testWidgets('backup older than 36 hours is flagged', (tester) async {
      final old = DateTime.now().toUtc().subtract(const Duration(hours: 50)).toIso8601String();
      await open(tester, 'Admin', (r) => backup({'configured': true, 'count': 3, 'lastBackupAt': old, 'lastBackupFile': 'a.dump', 'lastBackupSizeBytes': 2048}), section: 'admin');
      expect(find.text('Último backup está velho'), findsOneWidget);
    });

    testWidgets('no backup found and unconfigured folder have their own messages', (tester) async {
      await open(tester, 'Admin', (r) => backup({'configured': true, 'count': 0}), section: 'admin');
      expect(find.text('Nenhum backup encontrado'), findsOneWidget);
      await tapV(tester, find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      await open(tester, 'Admin', (r) => backup({'configured': false, 'count': 0}), section: 'admin');
      expect(find.text('Pasta de backups não ligada ao servidor'), findsOneWidget);
    });

    group('fonte dos dados', () {
      Future<(Session, List<http.Request>)> sourceScreen(WidgetTester tester, {int preview = 4}) async {
        final r = await open(tester, 'Admin', (r) async {
          if (r.url.path == '/api/admin/backup-status') return json({'configured': false, 'count': 0});
          if (r.url.path == '/api/admin/data-source' && r.method == 'GET') {
            return json([
              {'entity': 'SalesOrder', 'manual': 12, 'imported': 300, 'test': 1},
              {'entity': 'Customer', 'manual': 40, 'imported': 800, 'test': 0},
            ]);
          }
          if (r.url.path == '/api/admin/data-source') {
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            return json({'entity': body['entity'], 'rows': body['apply'] == true ? preview : preview, 'applied': body['apply']});
          }
          return json({});
        }, section: 'admin');
        await tapV(tester, find.byKey(const ValueKey('settings-open-data-source')));
        await tester.pumpAndSettle();
        return r;
      }

      testWidgets('shows counts in the order of the registry, with Portuguese names', (tester) async {
        await sourceScreen(tester);
        expect(find.text('Clientes'), findsOneWidget);
        expect(find.text('Pedidos de venda'), findsOneWidget);
        final customers = tester.getTopLeft(find.text('Clientes')).dy;
        final orders = tester.getTopLeft(find.text('Pedidos de venda')).dy;
        expect(customers, lessThan(orders));
        expect(find.text('800'), findsOneWidget);
      });

      testWidgets('marking is previewed, confirmed, then applied', (tester) async {
        final (_, log) = await sourceScreen(tester);
        await tapV(tester, find.byKey(const ValueKey('data-source-menu-Customer')));
        await tester.pumpAndSettle();
        await tapV(tester, find.text('Manual para Teste'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Marcar 4 de Clientes como Teste?'), findsOneWidget);
        var posts = log.where((r) => r.method == 'POST').map((r) => jsonDecode(r.body) as Map<String, dynamic>).toList();
        expect(posts.single, {'entity': 'Customer', 'allManual': true, 'from': 'Manual', 'target': 'Test', 'apply': false});
        await tapV(tester, find.byKey(const ValueKey('data-source-confirm')));
        await tester.pumpAndSettle();
        posts = log.where((r) => r.method == 'POST').map((r) => jsonDecode(r.body) as Map<String, dynamic>).toList();
        expect(posts.last['apply'], isTrue);
        expect(find.text('4 de Clientes marcados como Teste'), findsOneWidget);
      });

      testWidgets('nothing to change is said and nothing is applied', (tester) async {
        final (_, log) = await sourceScreen(tester, preview: 0);
        await tapV(tester, find.byKey(const ValueKey('data-source-menu-Customer')));
        await tester.pumpAndSettle();
        await tapV(tester, find.text('Teste para Manual'));
        await tester.pumpAndSettle();
        expect(find.text('Nada a mudar em Clientes'), findsOneWidget);
        expect(log.where((r) => r.method == 'POST'), hasLength(1));
      });
    });
  });

  group('desconexão por inatividade', () {
    testWidgets('signs out after the chosen idle time and tells the login screen why', (tester) async {
      var now = DateTime(2026, 11, 1, 9);
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: MockClient((r) async => json({})), token: 'tok'))
        ..username = 'ana'
        ..expiresAt = DateTime.now().add(const Duration(hours: 1))
        ..idleLockMinutes = 15;
      await tester.pumpWidget(
        MaterialApp(
          home: IdleGuard(session: session, checkEvery: const Duration(seconds: 1), now: () => now, child: const Scaffold(body: Text('conteúdo'))),
        ),
      );
      now = now.add(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(session.api.token, 'tok', reason: 'still within the limit');
      await tester.tapAt(const Offset(10, 10));
      now = now.add(const Duration(minutes: 14));
      await tester.pump(const Duration(seconds: 1));
      expect(session.api.token, 'tok', reason: 'a click restarted the clock');
      now = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(session.api.token, isNull);
      expect(session.idleSignedOut, isTrue);
    });

    testWidgets('never means never', (tester) async {
      var now = DateTime(2026, 11, 1, 9);
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: MockClient((r) async => json({})), token: 'tok'))..expiresAt = DateTime.now().add(const Duration(hours: 1));
      await tester.pumpWidget(MaterialApp(home: IdleGuard(session: session, checkEvery: const Duration(seconds: 1), now: () => now, child: const SizedBox())));
      now = now.add(const Duration(hours: 9));
      await tester.pump(const Duration(seconds: 1));
      expect(session.api.token, 'tok');
    });
  });
}

/// Taps [finder] after scrolling it into view; the settings panes scroll.
Future<void> tapV(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}
