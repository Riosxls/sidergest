import 'package:ebt_engenharia/screens/shell.dart';
import 'package:ebt_engenharia/widgets/discard_guard.dart';
import 'package:ebt_engenharia/widgets/record_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dashboard_test.dart' show pumpShell;
import 'esc_back_test.dart' show esc;
import 'nav.dart';

Future<void> chord(WidgetTester tester, LogicalKeyboardKey mod, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(mod);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(mod);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a link back to a record with unsaved edits asks before closing the pages above it', (tester) async {
    final trail = RecordTrail();
    var dirty = true;
    Widget page(String name, [VoidCallback? next]) => Scaffold(
      body: Column(
        children: [
          Text(name),
          if (next != null) TextButton(onPressed: next, child: const Text('go')),
        ],
      ),
    );
    Widget order(BuildContext _) => Builder(builder: (c) => page('order', () => pushRecord<void>(c, 'quote', 1, (_) => page('again'))));
    Widget quote(BuildContext _) => DiscardGuard(
      isDirty: () => dirty,
      child: Builder(builder: (c) => page('quote', () => pushRecord<void>(c, 'order', 2, order))),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [trail],
        home: Builder(builder: (c) => page('home', () => pushRecord<void>(c, 'quote', 1, quote))),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('order'), findsOneWidget);
    dirty = false;
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsNothing);
    expect(find.text('order'), findsNothing);
    expect(find.text('quote'), findsOneWidget);
  });

  testWidgets('sidebar lists the modules on the Painel and only the current module inside one', (tester) async {
    await pumpShell(tester, 'Admin');
    for (final m in ['Comercial', 'Engenharia', 'Estoque', 'Suprimentos', 'PCP']) {
      expect(find.byKey(ValueKey('nav-module:$m')), findsOneWidget);
    }
    expect(find.widgetWithText(ListTile, 'Saldos'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-module:Estoque')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-section-Estoque')), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Saldos'), findsOneWidget);
    // Other subjects are not listed while working in this one.
    for (final m in ['Comercial', 'Engenharia', 'Suprimentos', 'PCP']) {
      expect(find.byKey(ValueKey('nav-module:$m')), findsNothing);
    }
    expect(find.widgetWithText(ListTile, 'Apontamentos'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Painel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-module:PCP')), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Saldos'), findsNothing);
  });

  testWidgets('Ctrl+number opens a module, Alt+left goes back and Alt+right forward', (tester) async {
    await pumpShell(tester, 'Admin');
    await chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.digit2);
    expect(find.byKey(const ValueKey('module-PCP')), findsNothing);
    expect(find.byKey(const ValueKey('nav-/api/products')), findsOneWidget);
    await chord(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowLeft);
    expect(find.byKey(const ValueKey('module-PCP')), findsOneWidget);
    await chord(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowRight);
    expect(find.byKey(const ValueKey('nav-/api/products')), findsOneWidget);
    await chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.digit0);
    expect(find.byKey(const ValueKey('module-PCP')), findsOneWidget);
  });

  testWidgets('open record pages show a breadcrumb and previous / next buttons; the screen crumb closes them; the place is remembered', (tester) async {
    final (session, _) = await pumpShell(tester, 'Admin');
    await openScreen(tester, 'PCP', 'production-orders');
    expect(Shell.lastLocation[session]!.path, '/s/production-orders');
    final inner = tester.state<NavigatorState>(find.byType(Navigator).last);
    inner.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'record:quote:5', arguments: <int>[5, 6, 7]),
        builder: (_) => const Scaffold(body: Text('registro aberto')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('registro aberto'), findsOneWidget);
    expect(find.text('Orçamento'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.byTooltip('Registro anterior'), findsOneWidget);
    expect(Shell.lastLocation[session]!.path, '/s/production-orders/r/quote/5');
    await tester.tap(find.text('PCP › Ordens de fabricação'));
    await tester.pumpAndSettle();
    expect(find.text('registro aberto'), findsNothing);
    expect(find.text('Orçamento'), findsNothing);
  });

  testWidgets('Esc closes an open record page before leaving the screen', (tester) async {
    await pumpShell(tester, 'Admin');
    await openScreen(tester, 'PCP', 'production-orders');
    final inner = tester.state<NavigatorState>(find.byType(Navigator).last);
    inner.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'record:quote:5'),
        builder: (_) => const Scaffold(body: Text('registro aberto')),
      ),
    );
    await tester.pumpAndSettle();
    await esc(tester);
    expect(find.text('registro aberto'), findsNothing);
    expect(find.byKey(const ValueKey('link-production-orders')), findsNothing);
  });
}
