import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/widgets/entity_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EntityFormDialog(
                api: ApiClient(baseUrl: 'http://api.test'),
                title: 'Novo',
                fields: const [FieldSpec('name', 'Nome')],
                onSubmit: (_) async => null,
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('leaving a form with edits asks before discarding', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('field-name')), 'abc');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('Novo'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('Novo'), findsNothing);
  });

  testWidgets('leaving an untouched form does not ask', (tester) async {
    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsNothing);
    expect(find.text('Novo'), findsNothing);
  });
}
