import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/command_palette.dart';
import 'package:ebt_engenharia/widgets/record_list.dart';
import 'package:ebt_engenharia/widgets/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _login(String token) => {
  'token': token,
  'username': 'ana',
  'role': 'Reader',
  'permissions': ['read'],
  'expiresAt': DateTime.now().add(const Duration(minutes: 60)).toUtc().toIso8601String(),
  'refreshToken': 'r-$token',
  'refreshExpiresAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
};

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('change password', () {
    late List<http.Request> seen;
    late int status;

    Future<Session> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      seen = [];
      status = 200;
      final client = MockClient((r) async {
        seen.add(r);
        if (status == 400) {
          return http.Response(
            jsonEncode({
              'errors': {
                'currentPassword': ['Incorrect password'],
              },
            }),
            400,
          );
        }
        return http.Response(jsonEncode(_login('new-token')), 200);
      });
      final session = Session(api: ApiClient(baseUrl: 'http://x', client: client, token: 'old-token'))
        ..username = 'ana'
        ..permissions = {'read'};
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(body: TextButton(onPressed: () => showChangePassword(c, session), child: const Text('abrir'))),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return session;
    }

    Future<void> fill(WidgetTester tester, String current, String next, String again) async {
      await tester.enterText(find.byKey(const ValueKey('pw-current')), current);
      await tester.enterText(find.byKey(const ValueKey('pw-new')), next);
      await tester.enterText(find.byKey(const ValueKey('pw-again')), again);
      await tester.tap(find.byKey(const ValueKey('pw-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('mistakes are caught before anything is sent', (tester) async {
      await open(tester);
      await fill(tester, 'old-password-1', 'short', 'short');
      expect(find.textContaining('pelo menos $minPasswordLength caracteres'), findsOneWidget);
      await fill(tester, 'old-password-1', 'old-password-1', 'old-password-1');
      expect(find.textContaining('diferente da atual'), findsOneWidget);
      await fill(tester, 'old-password-1', 'new-password-22', 'new-password-23');
      expect(find.textContaining('confirmação'), findsOneWidget);
      expect(seen, isEmpty);
    });

    testWidgets('success swaps in the new tokens and closes', (tester) async {
      final s = await open(tester);
      await fill(tester, 'old-password-1', 'new-password-22', 'new-password-22');
      expect(seen.single.url.path, '/api/auth/password');
      expect(jsonDecode(seen.single.body), {'currentPassword': 'old-password-1', 'newPassword': 'new-password-22'});
      expect(s.api.token, 'new-token');
      expect(s.api.refreshToken, 'r-new-token');
      expect(find.text('Alterar minha senha'), findsNothing);
    });

    testWidgets('a wrong current password is shown by field and the dialog stays', (tester) async {
      await open(tester);
      status = 400;
      await fill(tester, 'wrong-password-1', 'new-password-22', 'new-password-22');
      expect(find.textContaining('Senha atual: Incorrect password'), findsOneWidget);
      expect(find.text('Alterar minha senha'), findsOneWidget);
    });
  });

  test('clearing the app cache forgets loaded names and recent items but not the login', () async {
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      return http.Response(jsonEncode({'id': 1, 'name': 'Cliente A', 'code': 'A'}), 200);
    });
    final session = Session(api: ApiClient(baseUrl: 'http://x', client: client, token: 't'));
    await NameCache.name(session.api, '/api/customers', 1);
    await NameCache.name(session.api, '/api/customers', 1);
    expect(calls, 1, reason: 'second lookup comes from the cache');
    await RecentStore.add(const RecentItem('screen', 'customers', 'Clientes'));
    expect(await RecentStore.load(), isNotEmpty);

    await clearLocalCache(session);
    await NameCache.name(session.api, '/api/customers', 1);
    expect(calls, 2);
    expect(await RecentStore.load(), isEmpty);
    expect(session.api.token, 't');
  });

  test('density and text size are saved and used by the theme', () async {
    final s = Session();
    await s.setComfortable(true);
    await s.setTextScale(1.3);
    final again = Session();
    await again.restore();
    expect(again.comfortable, isTrue);
    expect(again.textScale, 1.3);
    expect(appTheme(Brightness.light, comfortable: true).visualDensity, VisualDensity.standard);
    expect(appTheme(Brightness.light).visualDensity, VisualDensity.compact);
  });
}
