import 'package:ebt_engenharia/main.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('changing the text size resizes the rendered text of the whole app', (tester) async {
    final s = Session();
    await tester.pumpWidget(EbtApp(session: s));
    await tester.pumpAndSettle();
    final text = find.text('Entrar').hitTestable();
    final target = text.evaluate().isNotEmpty ? text : find.byType(Text).first;
    final before = tester.getSize(target.first);
    await s.setTextScale(1.5);
    await tester.pumpAndSettle();
    final after = tester.getSize(target.first);
    expect(after.height, greaterThan(before.height), reason: 'before $before after $after');
  });
}
