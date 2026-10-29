import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:ebt_engenharia/widgets/entity_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lead time days and delivery date stay in sync', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('pt', 'BR')],
        home: Scaffold(
          body: EntityFormDialog(
            api: ApiClient(baseUrl: 'http://api.test'),
            title: 'x',
            fields: salesLineFields.where((f) => f.key == 'leadTimeDays' || f.key == 'deliveryDate').toList(),
            onSubmit: (_) async => null,
          ),
        ),
      ),
    );
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    await tester.enterText(find.byKey(const ValueKey('field-leadTimeDays')), '9');
    await tester.pump();
    String text(String k) => tester.widget<TextField>(find.byKey(ValueKey('field-$k'))).controller!.text;
    expect(text('deliveryDate'), fmtDay(isoDate(today.add(const Duration(days: 9)))));
    await tester.enterText(find.byKey(const ValueKey('field-deliveryDate')), fmtDay(isoDate(today.add(const Duration(days: 20)))));
    await tester.pump();
    expect(text('leadTimeDays'), '20');
  });
}
