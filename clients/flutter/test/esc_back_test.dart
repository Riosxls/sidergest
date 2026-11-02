import 'package:ebt_engenharia/widgets/discard_guard.dart';
import 'package:ebt_engenharia/widgets/esc_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dashboard_test.dart' show pumpShell;
import 'nav.dart';
import 'settings_screens_test.dart' as settings show open, none, goTo;

Future<void> esc(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

Future<void> pumpApp(WidgetTester tester, {bool dirty = false}) async {
  final key = GlobalKey<NavigatorState>();
  final observer = EscRouteObserver();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: key,
      navigatorObservers: [observer],
      builder: (context, child) => EscBack(navigatorKey: key, observer: observer, child: child!),
      home: Builder(
        builder: (c) => Scaffold(
          body: Column(
            children: [
              const Text('raiz'),
              TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DiscardGuard(
                      isDirty: () => dirty,
                      child: Scaffold(
                        body: Column(
                          children: [
                            const Text('pagina'),
                            Builder(
                              builder: (p) => TextButton(
                                onPressed: () => showDialog<void>(
                                  context: p,
                                  builder: (_) => const AlertDialog(title: Text('dialogo')),
                                ),
                                child: const Text('dialogo'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Esc pops a pushed page and does nothing on the root', (tester) async {
    await pumpApp(tester);
    expect(find.text('pagina'), findsOneWidget);
    await esc(tester);
    expect(find.text('pagina'), findsNothing);
    expect(find.text('raiz'), findsOneWidget);
    await esc(tester);
    expect(find.text('raiz'), findsOneWidget);
  });

  testWidgets('Esc on a dirty guarded page asks before discarding', (tester) async {
    await pumpApp(tester, dirty: true);
    await esc(tester);
    expect(find.text('Descartar alterações?'), findsOneWidget);
    expect(find.text('pagina'), findsOneWidget);
    await esc(tester);
    expect(find.text('Descartar alterações?'), findsNothing);
    expect(find.text('pagina'), findsOneWidget);
    await esc(tester);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('pagina'), findsNothing);
  });

  testWidgets('Esc with a dialog on top closes only the dialog', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('dialogo'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await esc(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('pagina'), findsOneWidget);
  });

  testWidgets('Esc ignores key combinations', (tester) async {
    await pumpApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('pagina'), findsOneWidget);
  });

  testWidgets('Shell: Esc does nothing on the Painel and returns from a module screen to it', (tester) async {
    await pumpShell(tester, 'Admin');
    await esc(tester);
    expect(find.byKey(const ValueKey('module-PCP')), findsOneWidget);
    await openModule(tester, 'PCP');
    expect(find.text('Telas'), findsOneWidget);
    await esc(tester);
    expect(find.byKey(const ValueKey('module-PCP')), findsOneWidget);
    expect(find.text('Telas'), findsNothing);
  });

  testWidgets('Shell: first Esc only unfocuses a text field', (tester) async {
    await pumpShell(tester, 'Admin');
    await openModule(tester, 'PCP');
    await tester.tap(find.byKey(const ValueKey('link-production-orders')));
    await tester.pumpAndSettle();
    final field = find.byType(EditableText);
    expect(field, findsWidgets);
    await tester.tap(field.first);
    await tester.pump();
    await esc(tester);
    expect(find.byKey(const ValueKey('module-PCP')), findsNothing);
    // Esc steps back one screen: the PCP overview it came from, then the Painel.
    await esc(tester);
    expect(find.byKey(const ValueKey('module-PCP')), findsNothing);
    expect(find.byKey(const ValueKey('link-production-orders')), findsOneWidget);
    await esc(tester);
    expect(find.byKey(const ValueKey('module-PCP')), findsOneWidget);
  });

  testWidgets('settings dialog: Esc closes the sub-view, then the dialog', (tester) async {
    await settings.open(tester, 'SalesManager', (r) async => settings.none(r), section: 'general');
    await tester.tap(find.text('Atalhos de teclado'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-sub-back')), findsOneWidget);
    await esc(tester);
    expect(find.byKey(const ValueKey('settings-sub-back')), findsNothing);
    expect(find.text('Tela inicial'), findsOneWidget);
    await esc(tester);
    expect(find.text('Tela inicial'), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('settings dialog (narrow): Esc returns from a section to the menu, then closes', (tester) async {
    await settings.open(tester, 'Reader', (r) async => settings.none(r));
    tester.view.physicalSize = const Size(500, 900);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-nav-general')), findsOneWidget);
    await settings.goTo(tester, 'general');
    expect(find.byKey(const ValueKey('settings-back-to-menu')), findsOneWidget);
    await esc(tester);
    expect(find.byKey(const ValueKey('settings-back-to-menu')), findsNothing);
    expect(find.byKey(const ValueKey('settings-nav-general')), findsOneWidget);
    await esc(tester);
    expect(find.byKey(const ValueKey('settings-nav-general')), findsNothing);
  });
}
