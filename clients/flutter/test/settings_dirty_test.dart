import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/main.dart' show appTheme;
import 'package:ebt_engenharia/screens/settings/settings_dialog.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';

http.Response _json(Object? body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> _open(WidgetTester tester, {required bool wide}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = wide ? const Size(1600, 1200) : const Size(500, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = MockClient((r) async {
    if (r.url.path == '/api/admin/backup-settings') {
      return _json({'enabled': false, 'frequency': 'Daily', 'timeOfDay': '22:00', 'weekday': 1, 'destination': null, 'keep': 14});
    }
    return _json({});
  });
  final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
    ..username = 'ana'
    ..role = 'Admin'
    ..permissions = rolePermissions['Admin']!;
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (c) => Scaffold(body: TextButton(onPressed: () => showUserSettings(c, session, section: 'backup'), child: const Text('abrir'))),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _dirty(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('backup-keep')), '30');
  await tester.pump();
}

void main() {
  const prompt = 'Descartar alterações?';

  Future<void> expectPromptThenStay(WidgetTester tester) async {
    expect(find.text(prompt), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text(prompt), findsNothing);
    expect(find.byKey(const ValueKey('backup-keep')), findsOneWidget, reason: 'still editing');
  }

  testWidgets('section switch and the close X ask when dirty', (tester) async {
    await _open(tester, wide: true);
    await _dirty(tester);
    await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
    await tester.pumpAndSettle();
    await expectPromptThenStay(tester);
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    await expectPromptThenStay(tester);
    expect(find.byType(SettingsDialog), findsOneWidget);
  });

  testWidgets('Esc asks once and Continuar editando keeps the form', (tester) async {
    await _open(tester, wide: true);
    await _dirty(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await expectPromptThenStay(tester);
    expect(find.byType(SettingsDialog), findsOneWidget);
  });

  testWidgets('Esc on a clean form closes the window without asking', (tester) async {
    await _open(tester, wide: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(prompt), findsNothing);
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('clean form: back, section switch and close do not ask', (tester) async {
    await _open(tester, wide: true);
    await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
    await tester.pumpAndSettle();
    expect(find.text(prompt), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('narrow window: Voltar às configurações asks when dirty', (tester) async {
    await _open(tester, wide: false);
    await _dirty(tester);
    await tester.tap(find.byKey(const ValueKey('settings-back-to-menu')));
    await tester.pumpAndSettle();
    await expectPromptThenStay(tester);
  });

  testWidgets('discarding through the close X closes the window', (tester) async {
    await _open(tester, wide: true);
    await _dirty(tester);
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });
}
