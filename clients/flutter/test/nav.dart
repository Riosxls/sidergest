import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openModule(WidgetTester tester, String module) async {
  if (find.byKey(ValueKey('module-$module')).evaluate().isEmpty) {
    await tester.tap(find.widgetWithText(ListTile, 'Painel'));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(ValueKey('module-$module')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('module-$module')));
  await tester.pumpAndSettle();
}

Future<void> openScreen(WidgetTester tester, String module, String id) async {
  await openModule(tester, module);
  // Narrow layouts list the module's screens as cards; wide ones only have the sidebar.
  final link = find.byKey(ValueKey('link-$id'));
  final target = link.evaluate().isNotEmpty ? link : find.byKey(ValueKey('nav-$id'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}
