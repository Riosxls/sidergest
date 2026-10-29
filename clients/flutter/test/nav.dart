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
  await tester.ensureVisible(find.byKey(ValueKey('link-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('link-$id')));
  await tester.pumpAndSettle();
}
