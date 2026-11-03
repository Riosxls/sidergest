import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/widgets/drafts.dart';
import 'package:ebt_engenharia/widgets/entity_form.dart';
import 'package:ebt_engenharia/widgets/load_error.dart';
import 'package:ebt_engenharia/widgets/record_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_test.dart' show pumpShell;
import 'nav.dart';

ApiClient _api(MockClient c) => ApiClient(baseUrl: 'http://api.test', client: c, token: 'tok');

void main() {
  testWidgets('a record that cannot load says why and offers to try again', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordLoader(
          title: 'Cliente',
          load: () async {
            if (++calls == 1) throw Exception('falhou');
            return {'name': 'ACME'};
          },
          builder: (d) => Scaffold(body: Text('aberto ${d['name']}')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tentar novamente'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('aberto ACME'), findsOneWidget);
  });

  testWidgets('a list moves with the arrow keys, opens with Enter and gives / to the search box', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final opened = <int>[];
    final client = MockClient(
      (r) async => http.Response(
        jsonEncode([
          {'id': 1, 'name': 'A'},
          {'id': 2, 'name': 'B'},
        ]),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordList(api: _api(client), path: '/api/things', columns: [col('Nome', 'name')], onTap: (e) async => opened.add(e['id'] as int)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, [1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const ValueKey('record-search')));
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('a form open when the session ends is offered again, once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((r) async => http.Response('{}', 200));
    Widget form() => MaterialApp(
      home: Scaffold(
        body: EntityFormDialog(api: _api(client), title: 'Cliente teste', fields: const [FieldSpec('name', 'Nome')], onSubmit: (b) async => b),
      ),
    );
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-name')), 'Rascunho 1');
    await tester.pump();
    DraftRegistry.saveAll();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    expect(find.textContaining('Rascunho recuperado'), findsOneWidget);
    expect(find.text('Rascunho 1'), findsOneWidget);
    // Leaving without saving drops it.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    expect(find.textContaining('Rascunho recuperado'), findsNothing);
  });

  testWidgets('a screen can be starred and shows under Fixados; a pasted link is offered in the search', (tester) async {
    await pumpShell(tester, 'Admin');
    await openScreen(tester, 'PCP', 'production-orders');
    await tester.tap(find.byKey(const ValueKey('pin-screen')));
    await tester.pumpAndSettle();
    expect(find.text('Fixados'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-pin-production-orders-')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pin-screen')));
    await tester.pumpAndSettle();
    expect(find.text('Fixados'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '/s/audit');
    await tester.pumpAndSettle();
    expect(find.text('Abrir link colado'), findsOneWidget);
    await tester.tap(find.text('Abrir link colado'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Auditoria')), findsOneWidget);
    expect(find.byKey(const ValueKey('link-production-orders')), findsNothing);
  });
}
