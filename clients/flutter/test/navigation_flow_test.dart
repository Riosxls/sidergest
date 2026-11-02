import 'package:ebt_engenharia/widgets/record_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dashboard_test.dart' show pumpShell;
import 'esc_back_test.dart' show esc;
import 'nav.dart';

void main() {
  testWidgets('Shell: Esc returns to the screen visited before, which keeps its search text', (tester) async {
    await pumpShell(tester, 'Admin');
    await openScreen(tester, 'PCP', 'production-orders');
    await tester.enterText(find.byType(EditableText).first, 'abc');
    await tester.pump();
    await esc(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Apontamentos'));
    await tester.pumpAndSettle();
    expect(find.text('abc'), findsNothing);
    await esc(tester);
    expect(find.text('abc'), findsOneWidget);
  });

  testWidgets('Shell (wide): the sidebar stays on screen and Esc steps back through visited screens', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpShell(tester, 'Admin');
    await openScreen(tester, 'PCP', 'production-orders');
    expect(find.widgetWithText(ListTile, 'Apontamentos'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Apontamentos'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Voltar'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Ordens de fabricação'), findsOneWidget);
  });

  testWidgets('pushRecord returns to a record already open instead of stacking it again', (tester) async {
    final trail = RecordTrail();
    final key = GlobalKey<NavigatorState>();
    final seen = <String>[];
    Widget page(String name, [VoidCallback? next]) => Scaffold(
      body: Column(
        children: [
          Text(name),
          if (next != null) TextButton(onPressed: next, child: const Text('go')),
        ],
      ),
    );
    Widget order(BuildContext _) =>
        Builder(builder: (c) => page('order', () => pushRecord<void>(c, 'quote', 1, (_) => page('again')).then((_) => seen.add('popped'))));
    Widget quote(BuildContext _) => Builder(builder: (c) => page('quote', () => pushRecord<void>(c, 'order', 2, order)));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [trail],
        home: Builder(builder: (c) => page('home', () => pushRecord<void>(c, 'quote', 1, quote))),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('order'), findsOneWidget);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('again'), findsNothing);
    expect(find.text('quote'), findsOneWidget);
    expect(seen, ['popped']);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
