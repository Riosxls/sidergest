import 'dart:async';
import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart';
import 'package:ebt_engenharia/screens/login.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('signing out closes pushed screens and dialogs so none stays open over the login page', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((r) async {
      if (r.url.path == '/api/auth/login') {
        return _json({
          'token': 'tok',
          'expiresAt': DateTime.now().add(const Duration(hours: 8)).toUtc().toIso8601String(),
          'refreshToken': 'rt-1',
          'refreshExpiresAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
          'username': 'eng',
          'role': 'Engineering',
          'permissions': ['read'],
        });
      }
      return _json({'items': [], 'total': 0, 'skip': 0, 'take': 50});
    });
    final session = Session(api: ApiClient(baseUrl: 'http://x', client: client));
    await session.login('http://x', 'eng', 'pw');
    await tester.pumpWidget(EbtApp(session: session));
    await tester.pump(const Duration(milliseconds: 200));

    final nav = Navigator.of(tester.element(find.byType(Scaffold).first));
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('tela aberta'))));
    await tester.pumpAndSettle();
    expect(find.text('tela aberta'), findsOneWidget);
    unawaited(showDialog<void>(context: tester.element(find.text('tela aberta')), builder: (_) => const AlertDialog(content: Text('dialogo aberto'))));
    await tester.pumpAndSettle();
    expect(find.text('dialogo aberto'), findsOneWidget);

    await session.logout();
    await tester.pumpAndSettle();
    expect(find.text('tela aberta'), findsNothing);
    expect(find.text('dialogo aberto'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
