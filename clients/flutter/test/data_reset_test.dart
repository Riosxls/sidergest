import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/data_reset.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<List<http.Request>> open(WidgetTester tester, {int status = 200}) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seen = <http.Request>[];
    final client = MockClient((r) async {
      seen.add(r);
      if (r.url.path.endsWith('/preview')) {
        return http.Response(
          jsonEncode({
            'tables': [
              {'table': 'quotes', 'rows': 3},
              {'table': 'sales_orders', 'rows': 2},
              {'table': 'deliveries', 'rows': 0},
            ],
            'totalRows': 5,
          }),
          200,
        );
      }
      if (status != 200) return http.Response(jsonEncode({'title': 'Cannot clear data', 'detail': 'stock_documents still has records'}), status);
      return http.Response(jsonEncode({'tables': [], 'totalRows': 5}), 200);
    });
    final session = Session(api: ApiClient(baseUrl: 'http://x', client: client));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(body: TextButton(onPressed: () => showDataResetDialog(c, session), child: const Text('abrir'))),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return seen;
  }

  testWidgets('preview first, then the confirmation word unlocks the delete', (tester) async {
    final seen = await open(tester);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('reset-Sales'))).value, isTrue);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('reset-Production'))).value, isFalse, reason: 'imported legacy data is opt-in');
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('reset-Stock'))).value, isFalse, reason: 'stock is opt-in');
    expect(find.byKey(const ValueKey('reset-run')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reset-preview')));
    await tester.pumpAndSettle();
    expect(jsonDecode(seen.single.body)['scopes'], ['Sales']);
    expect(find.text('Serão apagados 5 registros:'), findsOneWidget);
    expect(find.text('Orçamentos'), findsOneWidget);
    expect(find.text('Entregas'), findsNothing, reason: 'empty tables are not listed');

    FilledButton run() => tester.widget<FilledButton>(find.byKey(const ValueKey('reset-run')));
    expect(run().onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('reset-confirm')), 'limpar');
    await tester.pump();
    expect(run().onPressed, isNull, reason: 'the word is case sensitive');
    await tester.enterText(find.byKey(const ValueKey('reset-confirm')), 'LIMPAR');
    await tester.pump();
    expect(run().onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('reset-run')));
    await tester.pumpAndSettle();
    final del = seen.last;
    expect(del.url.path, '/api/admin/data-reset');
    expect(jsonDecode(del.body)['confirm'], 'LIMPAR');
    expect(find.text('Limpar dados de movimento'), findsNothing, reason: 'dialog closes on success');
  });

  testWidgets('changing the selection discards the preview and the typed word', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('reset-preview')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reset-confirm')), 'LIMPAR');
    await tester.tap(find.byKey(const ValueKey('reset-Stock')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-confirm')), findsNothing);
    expect(find.byKey(const ValueKey('reset-run')), findsNothing);
    expect(find.byKey(const ValueKey('reset-preview')), findsOneWidget);
  });

  testWidgets('a refusal from the server is shown and nothing closes', (tester) async {
    await open(tester, status: 409);
    await tester.tap(find.byKey(const ValueKey('reset-preview')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reset-confirm')), 'LIMPAR');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reset-run')));
    await tester.pumpAndSettle();
    expect(find.textContaining('stock_documents still has records'), findsOneWidget);
    expect(find.text('Limpar dados de movimento'), findsOneWidget);
  });
}
