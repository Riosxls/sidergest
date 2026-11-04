import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart' show appTheme;
import 'package:ebt_engenharia/screens/settings/settings_dialog.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/app_text_scale.dart';
import 'package:ebt_engenharia/widgets/idle_guard.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _login({Object? idle, Object? max}) => {
  'token': 'tok',
  'username': 'ana',
  'role': 'Admin',
  'permissions': ['read', 'admin'],
  'expiresAt': DateTime.now().add(const Duration(minutes: 60)).toUtc().toIso8601String(),
  'refreshToken': 'r-tok',
  'refreshExpiresAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
  'idleLockMinutes': ?idle,
  'maxIdleMinutes': ?max,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('server is the source of truth', () {
    test('login adopts idleLockMinutes and maxIdleMinutes', () async {
      final client = MockClient((r) async => r.url.path == '/api/auth/login' ? _json(_login(idle: 20, max: 20)) : _json({}));
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client));
      await session.login('http://api.test', 'ana', 'x');
      expect(session.idleLockMinutes, 20);
      expect(session.maxIdleMinutes, 20);
    });

    test('the stored-session restore refresh reads them from /auth/me', () async {
      FlutterSecureStorage.setMockInitialValues({
        'token': 'tok',
        'username': 'ana',
        'role': 'Admin',
        'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        'permissions': '["read"]',
      });
      final client = MockClient(
        (r) async => r.url.path == '/api/auth/me' ? _json({'role': 'Admin', 'permissions': ['read'], 'idleLockMinutes': 45, 'maxIdleMinutes': 60}) : _json({}),
      );
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client));
      await session.restore();
      expect(session.idleLockMinutes, 45);
      expect(session.maxIdleMinutes, 60);
    });

    test('setIdleLockMinutes PUTs the minutes and adopts the effective value', () async {
      final log = <http.Request>[];
      final client = MockClient((r) async {
        log.add(r);
        return _json({'idleLockMinutes': 30, 'maxIdleMinutes': 30});
      });
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 't'));
      final effective = await session.setIdleLockMinutes(60);
      expect(effective, 30);
      expect(session.idleLockMinutes, 30);
      expect(session.maxIdleMinutes, 30);
      expect(log.single.method, 'PUT');
      expect(log.single.url.path, '/api/auth/idle-lock');
      expect(log.single.body, '{"minutes":60}');
    });

    test('a refused PUT throws and keeps the value', () async {
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: MockClient((r) async => _json({'title': 'Falhou'}, 500)), token: 't'))
        ..idleLockMinutes = 15;
      await expectLater(session.setIdleLockMinutes(30), throwsA(anything));
      expect(session.idleLockMinutes, 15);
    });

    test('options: all by default, capped without Nunca, and an out-of-list value is added', () {
      final s = Session();
      expect(s.idleChoices, [0, 15, 30, 60]);
      s.idleLockMinutes = 45;
      expect(s.idleChoices, [0, 15, 30, 45, 60]);
      s
        ..maxIdleMinutes = 30
        ..idleLockMinutes = 30;
      expect(s.idleChoices, [15, 30]);
      s
        ..maxIdleMinutes = 20
        ..idleLockMinutes = 20;
      expect(s.idleChoices, [15, 20]);
    });
  });

  group('migration of the old per-device value', () {
    test('a local value is sent once when the server has none, then dropped', () async {
      SharedPreferences.setMockInitialValues({'idleLockMinutes': 30});
      final log = <http.Request>[];
      final client = MockClient((r) async {
        log.add(r);
        if (r.url.path == '/api/auth/login') return _json(_login(idle: 0, max: 0));
        if (r.url.path == '/api/auth/idle-lock') return _json({'idleLockMinutes': 30, 'maxIdleMinutes': 0});
        return _json({});
      });
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client));
      await session.login('http://api.test', 'ana', 'x');
      expect(log.where((r) => r.url.path == '/api/auth/idle-lock').single.body, '{"minutes":30}');
      expect(session.idleLockMinutes, 30);
      expect((await SharedPreferences.getInstance()).containsKey('idleLockMinutes'), isFalse);
    });

    test('a server value wins: nothing is sent and the pref is dropped', () async {
      SharedPreferences.setMockInitialValues({'idleLockMinutes': 30});
      final log = <http.Request>[];
      final client = MockClient((r) async {
        log.add(r);
        return r.url.path == '/api/auth/login' ? _json(_login(idle: 15, max: 0)) : _json({});
      });
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client));
      await session.login('http://api.test', 'ana', 'x');
      expect(log.any((r) => r.url.path == '/api/auth/idle-lock'), isFalse);
      expect(session.idleLockMinutes, 15);
      expect((await SharedPreferences.getInstance()).containsKey('idleLockMinutes'), isFalse);
    });

    test('a failed PUT keeps the pref for the next start', () async {
      SharedPreferences.setMockInitialValues({'idleLockMinutes': 60});
      final client = MockClient((r) async {
        if (r.url.path == '/api/auth/login') return _json(_login(idle: 0, max: 0));
        if (r.url.path == '/api/auth/idle-lock') return _json({'title': 'x'}, 500);
        return _json({});
      });
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client));
      await session.login('http://api.test', 'ana', 'x');
      expect((await SharedPreferences.getInstance()).getInt('idleLockMinutes'), 60);
    });
  });

  group('settings', () {
    Future<Session> open(WidgetTester tester, {required int idle, required int max, required Map<String, dynamic> put, List<http.Request>? log}) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = MockClient((r) async {
        log?.add(r);
        return r.url.path == '/api/auth/idle-lock' ? _json(put) : _json({});
      });
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
        ..username = 'ana'
        ..role = 'Reader'
        ..permissions = rolePermissions['Reader']!
        ..idleLockMinutes = idle
        ..maxIdleMinutes = max;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (c) => Scaffold(body: TextButton(onPressed: () => showUserSettings(c, session, section: 'account'), child: const Text('abrir'))),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('settings-idle')));
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('a cap hides Nunca and the larger options and shows the cap as selected', (tester) async {
      await open(tester, idle: 20, max: 20, put: {});
      final idle = find.byKey(const ValueKey('settings-idle'));
      expect(find.descendant(of: idle, matching: find.text('Nunca')), findsNothing);
      expect(find.descendant(of: idle, matching: find.text('30 min')), findsNothing);
      expect(find.descendant(of: idle, matching: find.text('60 min')), findsNothing);
      expect(find.descendant(of: idle, matching: find.text('15 min')), findsOneWidget);
      expect(find.descendant(of: idle, matching: find.text('20 minutos (limite do administrador)')), findsOneWidget);
      expect(find.textContaining('Sem usar o mouse nem o teclado'), findsOneWidget);
    });

    testWidgets('a server value outside the list is shown as an extra selected option', (tester) async {
      await open(tester, idle: 45, max: 0, put: {});
      final idle = find.byKey(const ValueKey('settings-idle'));
      expect(find.descendant(of: idle, matching: find.text('45 minutos (limite do administrador)')), findsOneWidget);
      expect(find.descendant(of: idle, matching: find.text('Nunca')), findsOneWidget);
    });

    testWidgets('when the server lowers the choice the user is told', (tester) async {
      final log = <http.Request>[];
      final session = await open(tester, idle: 0, max: 0, put: {'idleLockMinutes': 30, 'maxIdleMinutes': 30}, log: log);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('settings-idle')), matching: find.text('60 min')));
      await tester.pumpAndSettle();
      expect(log.where((r) => r.method == 'PUT').single.body, '{"minutes":60}');
      expect(session.idleLockMinutes, 30);
      expect(find.text('O administrador limita o bloqueio a 30 minutos.'), findsOneWidget);
    });
  });

  group('aviso de expiração', () {
    late DateTime now;
    late Session session;
    late List<http.Request> log;

    Future<void> pumpGuard(WidgetTester tester, {int minutes = 15}) async {
      now = DateTime(2026, 11, 1, 9);
      log = [];
      final client = MockClient((r) async {
        log.add(r);
        return _json({});
      });
      session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
        ..username = 'ana'
        ..expiresAt = DateTime.now().add(const Duration(hours: 1))
        ..idleLockMinutes = minutes;
      await tester.pumpWidget(
        MaterialApp(
          home: IdleGuard(session: session, checkEvery: const Duration(seconds: 1), now: () => now, child: const Scaffold(body: Text('conteúdo'))),
        ),
      );
    }

    Future<void> advance(WidgetTester tester, Duration d) async {
      now = now.add(d);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }

    testWidgets('appears 60 s before the sign-out with a live countdown', (tester) async {
      await pumpGuard(tester);
      await advance(tester, const Duration(minutes: 13, seconds: 50));
      expect(find.text('Sua sessão vai expirar'), findsNothing);
      await advance(tester, const Duration(seconds: 10));
      expect(find.text('Sua sessão vai expirar'), findsOneWidget);
      expect(find.textContaining('em 60 segundos'), findsOneWidget);
      await advance(tester, const Duration(seconds: 15));
      expect(find.textContaining('em 45 segundos'), findsOneWidget);
      expect(session.api.token, 'tok');
    });

    testWidgets('Continuar conectado closes it and restarts the clock', (tester) async {
      await pumpGuard(tester);
      await advance(tester, const Duration(minutes: 14, seconds: 30));
      expect(find.text('Sua sessão vai expirar'), findsOneWidget);
      await tester.tap(find.text('Continuar conectado'));
      await tester.pumpAndSettle();
      expect(find.text('Sua sessão vai expirar'), findsNothing);
      await advance(tester, const Duration(minutes: 10));
      expect(session.api.token, 'tok');
      expect(find.text('Sua sessão vai expirar'), findsNothing);
      expect(log.where((r) => r.url.path == '/api/auth/activity'), isNotEmpty);
    });

    testWidgets('Esc acts as Continuar conectado', (tester) async {
      await pumpGuard(tester);
      await advance(tester, const Duration(minutes: 14, seconds: 30));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Sua sessão vai expirar'), findsNothing);
      expect(session.api.token, 'tok');
      await advance(tester, const Duration(minutes: 13));
      expect(find.text('Sua sessão vai expirar'), findsNothing, reason: 'the clock restarted');
    });

    testWidgets('mouse movement does not hide the countdown; it reaches zero and signs out', (tester) async {
      await pumpGuard(tester);
      await advance(tester, const Duration(minutes: 14, seconds: 30));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(5, 5));
      await gesture.moveTo(const Offset(40, 40));
      await tester.pump();
      expect(find.text('Sua sessão vai expirar'), findsOneWidget);
      await advance(tester, const Duration(seconds: 29));
      expect(session.api.token, 'tok');
      await advance(tester, const Duration(seconds: 2));
      expect(session.api.token, isNull);
      expect(session.idleSignedOut, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Sua sessão vai expirar'), findsNothing);
    });

    testWidgets('Sair agora signs out at once', (tester) async {
      await pumpGuard(tester);
      await advance(tester, const Duration(minutes: 14, seconds: 30));
      await tester.tap(find.text('Sair agora'));
      await tester.pumpAndSettle();
      expect(session.api.token, isNull);
      expect(session.idleSignedOut, isTrue);
      expect(find.text('Sua sessão vai expirar'), findsNothing);
    });

    testWidgets('no lock, no warning, but the server still hears about activity', (tester) async {
      await pumpGuard(tester, minutes: 0);
      await advance(tester, const Duration(hours: 5));
      expect(find.text('Sua sessão vai expirar'), findsNothing);
      expect(session.api.token, 'tok');
      expect(log.where((r) => r.url.path == '/api/auth/activity'), isNotEmpty);
    });
  });

  group('text scale', () {
    Future<double> effective(WidgetTester tester, {required double os, required double app}) async {
      late double seen;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(os)),
          child: AppTextScale(
            factor: app,
            child: Builder(
              builder: (c) {
                seen = MediaQuery.textScalerOf(c).scale(1);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return seen;
    }

    for (final os in [1.0, 1.5]) {
      for (final app in [1.0, 1.15, 1.3]) {
        testWidgets('OS $os x app $app', (tester) async {
          final expected = (os * app).clamp(0.8, 2.0);
          expect(await effective(tester, os: os, app: app), closeTo(expected, 1e-9));
        });
      }
    }

    testWidgets('Normal keeps the OS scale and the result is clamped to 0.8..2.0', (tester) async {
      expect(await effective(tester, os: 1.5, app: 1.0), 1.5);
      expect(await effective(tester, os: 1.9, app: 1.3), 2.0);
      expect(await effective(tester, os: 0.5, app: 1.0), 0.8);
    });

    test('a stored text scale outside the choices snaps to the nearest one', () async {
      expect(Session.snapTextScale(1.0), 1.0);
      expect(Session.snapTextScale(1.2), 1.15);
      expect(Session.snapTextScale(1.5), 1.5);
      expect(Session.snapTextScale(1.9), 1.5);
      expect(Session.snapTextScale(0.5), 1.0);
      SharedPreferences.setMockInitialValues({'textScale': 1.1});
      final s = Session();
      await s.restore();
      expect(s.textScale, 1.15);
    });
  });
}