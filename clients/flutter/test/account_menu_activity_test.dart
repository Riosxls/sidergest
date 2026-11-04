import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart' show appTheme;
import 'package:ebt_engenharia/screens/settings/settings_dialog.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/alerts.dart';
import 'package:ebt_engenharia/widgets/user_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

typedef _Handler = Future<http.Response> Function(http.Request r);

Session _session(_Handler handler, List<http.Request> log, {String role = 'Admin'}) {
  final client = MockClient((r) async {
    log.add(r);
    return handler(r);
  });
  return Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok')..refreshToken = 'r-mine')
    ..username = 'ana'
    ..role = role
    ..permissions = rolePermissions[role]!;
}

Future<void> _pump(WidgetTester tester, Widget home, {Size size = const Size(1600, 1200)}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home,
    ),
  );
}

Future<void> _openSettings(WidgetTester tester, Session s, String section) async {
  await _pump(tester, Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showUserSettings(c, s, section: section), child: const Text('abrir')))));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<http.Response> _fail(http.Request r) async => _json({'title': 'x', 'status': 500}, 500);

void main() {
  group('account menu', () {
    Future<Session> menu(WidgetTester tester, {Size size = const Size(360, 800)}) async {
      final s = _session(_fail, [])
        ..displayName = 'Ana Souza'
        ..email = 'ana@ebt.com.br'
        ..previousLoginAt = DateTime(2026, 11, 3, 8, 15);
      await _pump(tester, Scaffold(appBar: AppBar(actions: [UserMenu(session: s)])), size: size);
      await tester.tap(find.byTooltip('Conta'));
      await tester.pumpAndSettle();
      return s;
    }

    testWidgets('header shows name, e-mail, role and the previous access, and still fits 360 px', (tester) async {
      await menu(tester);
      expect(find.text('Ana Souza'), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-email')), findsOneWidget);
      expect(find.text('ana@ebt.com.br'), findsOneWidget);
      expect(find.text('Administrador'), findsOneWidget);
      expect(find.text('Último acesso: 03/11/2026 08:15'), findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<String>, 'Configurações'), findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<String>, 'Sair'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without e-mail or a previous access those lines are left out', (tester) async {
      final s = _session(_fail, []);
      await _pump(tester, Scaffold(appBar: AppBar(actions: [UserMenu(session: s)])));
      await tester.tap(find.byTooltip('Conta'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-email')), findsNothing);
      expect(find.byKey(const ValueKey('menu-last-login')), findsNothing);
    });

    testWidgets('theme and text size change from the menu and stay open', (tester) async {
      final s = await menu(tester);
      await tester.tap(find.byTooltip('Escuro'));
      await tester.pumpAndSettle();
      expect(s.themeMode, ThemeMode.dark);
      expect(find.byKey(const ValueKey('menu-theme')), findsOneWidget, reason: 'the menu stays open');
      expect(find.text('Texto 100%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-text-larger')));
      await tester.pumpAndSettle();
      expect(s.textScale, 1.15);
      expect(find.text('Texto 115%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-text-smaller')));
      await tester.pumpAndSettle();
      expect(s.textScale, 1.0);
      final smaller = tester.widget<IconButton>(find.byKey(const ValueKey('menu-text-smaller')));
      expect(smaller.onPressed, isNull, reason: 'already at the smallest size');
    });

    testWidgets('Perfil, Configurações and Sair keep working', (tester) async {
      final s = await menu(tester);
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Perfil'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-profile-name')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Conta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Sair'));
      await tester.pumpAndSettle();
      expect(s.signedOutManually, isTrue);
    });
  });

  group('Minha atividade', () {
    Future<http.Response> activity(http.Request r) async => _json({
      'logins': [
        {'at': '2026-11-04T10:00:00Z', 'device': 'Windows', 'userAgent': null, 'ip': '10.0.0.5', 'current': true},
        {'at': '2026-11-02T09:30:00Z', 'device': null, 'userAgent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/120 Safari/537', 'ip': '10.0.0.9', 'current': false},
      ],
      'changes': [
        {'at': '2026-11-03T15:00:00Z', 'entity': 'Customer', 'entityId': '12', 'action': 'Update', 'summary': 'Prazo alterado'},
      ],
    });

    testWidgets('lists sign-ins with the current device marked, then the changes', (tester) async {
      final s = _session(activity, []);
      await _openSettings(tester, s, 'activity');
      expect(find.text('Este dispositivo'), findsOneWidget);
      expect(find.text('Chrome no Windows'), findsOneWidget);
      expect(find.textContaining('IP 10.0.0.9'), findsOneWidget);
      await tester.tap(find.text('Minhas alterações'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alterado · Cliente #12'), findsOneWidget);
      expect(find.textContaining('Prazo alterado'), findsOneWidget);
    });

    testWidgets('shows a skeleton while loading and empty states for no data', (tester) async {
      final s = _session((r) async => _json({}), []);
      await _openSettings(tester, s, 'activity');
      expect(find.byKey(const ValueKey('activity-logins-empty')), findsOneWidget);
      await tester.tap(find.text('Minhas alterações'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('activity-changes-empty')), findsOneWidget);
    });

    testWidgets('a failed load says so and retries', (tester) async {
      var fail = true;
      final s = _session((r) async => fail ? _fail(r) : activity(r), []);
      await _openSettings(tester, s, 'activity');
      expect(find.text('Tentar novamente'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Este dispositivo'), findsOneWidget);
    });

    testWidgets('the skeleton shows before the answer arrives', (tester) async {
      final s = _session((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return activity(r);
      }, []);
      await _pump(tester, Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showUserSettings(c, s, section: 'activity'), child: const Text('abrir')))));
      await tester.tap(find.text('abrir'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byKey(const ValueKey('activity-skeleton')), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('activity-skeleton')), findsNothing);
    });
  });

  group('Notificações', () {
    testWidgets('toggling a module saves it; always-on alerts cannot be switched', (tester) async {
      final log = <http.Request>[];
      final s = _session((r) async {
        if (r.method == 'PUT') return _json(jsonDecode(r.body));
        return _json({'mutedAlerts': <String>[], 'hideLegacy': false});
      }, log);
      await _openSettings(tester, s, 'notifications');
      await tester.tap(find.byKey(const ValueKey('notif-pcp')));
      await tester.pumpAndSettle();
      final put = log.lastWhere((r) => r.method == 'PUT');
      expect(put.url.path, '/api/auth/notification-prefs');
      expect(jsonDecode(put.body), {'mutedAlerts': ['pcp'], 'hideLegacy': false});
      expect(s.mutedAlerts, {'pcp'});
      await tester.tap(find.byKey(const ValueKey('notif-hide-legacy')));
      await tester.pumpAndSettle();
      expect(jsonDecode(log.lastWhere((r) => r.method == 'PUT').body), {'mutedAlerts': ['pcp'], 'hideLegacy': true});
      for (final k in ['notif-always-backup', 'notif-always-security']) {
        expect(tester.widget<SwitchListTile>(find.byKey(ValueKey(k))).onChanged, isNull, reason: k);
      }
    });

    testWidgets('a refused save puts the switch back and says so', (tester) async {
      final s = _session((r) async => r.method == 'PUT' ? _fail(r) : _json({'mutedAlerts': <String>[], 'hideLegacy': false}), []);
      await _openSettings(tester, s, 'notifications');
      await tester.tap(find.byKey(const ValueKey('notif-estoque')));
      await tester.pumpAndSettle();
      expect(s.mutedAlerts, isEmpty);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('notif-estoque'))).value, isTrue);
      expect(find.textContaining('Não foi possível salvar'), findsOneWidget);
    });

    testWidgets('preferences loaded from the server show as silenced', (tester) async {
      final s = _session((r) async => _json({'mutedAlerts': ['comercial'], 'hideLegacy': true}), []);
      await _openSettings(tester, s, 'notifications');
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('notif-comercial'))).value, isFalse);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('notif-hide-legacy'))).value, isTrue);
    });

    testWidgets('a silenced module leaves the bell count but the bell says how many were silenced', (tester) async {
      final s = _session((r) async => _json({'mutedAlerts': ['pcp'], 'hideLegacy': false}), []);
      s.alerts.update(all: const [
        AlertInfo(Icons.schedule, 'OFs atrasadas', 3, 'production-orders', null, 'pcp'),
        AlertInfo(Icons.block, 'Produtos bloqueados', 2, 'products', null, 'engenharia'),
      ]);
      await _pump(tester, Scaffold(appBar: AppBar(actions: [AlertBell(center: s.alerts, onNavigate: (_, [_]) {})])));
      expect(s.alerts.total, 5);
      await s.saveNotificationPrefs(muted: {'pcp'});
      await tester.pumpAndSettle();
      expect(s.alerts.total, 2);
      expect(s.alerts.silenced, 1);
      expect(find.byTooltip('Notificações (2)'), findsOneWidget);
      await tester.tap(find.byTooltip('Notificações (2)'));
      await tester.pumpAndSettle();
      expect(find.text('OFs atrasadas'), findsNothing);
      expect(find.text('Produtos bloqueados'), findsOneWidget);
      expect(find.text('1 alerta silenciado'), findsOneWidget);
    });
  });
}
