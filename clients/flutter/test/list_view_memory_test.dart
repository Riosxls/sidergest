import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/widgets/record_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpList(WidgetTester tester, {String? status}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = MockClient(
    (r) async => http.Response(
      jsonEncode([
        {'id': 1, 'name': 'B'},
        {'id': 2, 'name': 'A'},
      ]),
      200,
      headers: {'content-type': 'application/json'},
    ),
  );
  var value = status;
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: RecordList(
            api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'),
            path: '/api/things',
            columns: [col('Nome', 'name')],
            filters: [
              ChoiceFilter(label: 'Situação', value: value, choices: const {'Open': 'Aberta', 'Done': 'Feita'}, onChanged: (v) => setState(() => value = v)),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a list remembers its sort order and a chosen filter, and a value the screen sets itself wins', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpList(tester);
    await tester.tap(find.text('Nome'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-Situação')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feita').last);
    await tester.pumpAndSettle();
    final saved = jsonDecode((await SharedPreferences.getInstance()).getString('listView:/api/things')!) as Map<String, dynamic>;
    expect(saved['sort'], 0);
    expect(saved['filters'], {'Situação': 'Done'});

    await tester.pumpWidget(const SizedBox());
    await pumpList(tester);
    expect(find.text('Feita'), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).sortColumnIndex, 0);

    await tester.pumpWidget(const SizedBox());
    await pumpList(tester, status: 'Open');
    expect(find.text('Aberta'), findsOneWidget);
    expect(find.text('Feita'), findsNothing);
  });
}
