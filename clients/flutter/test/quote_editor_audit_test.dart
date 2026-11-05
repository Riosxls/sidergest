import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:ebt_engenharia/widgets/actions.dart';
import 'package:ebt_engenharia/widgets/drafts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sales_more_support.dart';

MoreFake _fake({num listPrice = 100}) {
  final f = MoreFake()..listPrice = listPrice;
  // The price table also says which IPI and ICMS the product carries.
  f.overrides['GET /api/sales/price'] = (r) => jsonResp({'productId': 7, 'unitPrice': f.listPrice, 'ipiPercent': 5, 'icmsPercent': 18});
  return f;
}

Future<void> _pickCustomer(WidgetTester tester) async {
  await tapKey(tester, 'quote-customer');
  await tester.tap(find.text('BTS Tubos').last);
  await tester.pumpAndSettle();
}

/// Opens the form of a new item; the product picker opens by itself, so the product is chosen straight away.
Future<void> _startItem(WidgetTester tester) async {
  await tapKey(tester, 'add-line');
  await tester.tap(find.text('TB-25 · Tubo 25,4 x 1,5').last);
  await tester.pumpAndSettle();
}

Future<void> _tapDialogButton(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilledButton, label).last);
  await tester.pumpAndSettle();
}

void main() {
  test('parseDecimal reads a pasted amount or percentage', () {
    expect(parseDecimal('R\$ 12,50'), 12.5);
    expect(parseDecimal('R\$ 1.234,56'), 1234.56);
    expect(parseDecimal('5 %'), 5);
    expect(parseDecimal('abc'), isNull);
  });

  testWidgets('picking a product shows the table price and the discount, and the taxes of the table reach the line', (tester) async {
    final f = _fake();
    await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
    await _pickCustomer(tester);
    await _startItem(tester);
    expect(find.textContaining('Tabela: R\$ 100,00'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('field-unitPrice'))).controller!.text, '100,00');
    await tester.enterText(find.byKey(const ValueKey('field-unitPrice')), '90');
    await tester.pumpAndSettle();
    expect(find.textContaining('desconto de 10%'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('field-quantity')), '10');
    await tester.enterText(find.byKey(const ValueKey('field-leadTimeDays')), '15');
    await _tapDialogButton(tester, 'Adicionar item');
    // 10 × 90 = 900 and 5% IPI = 45 show before anything is saved.
    expect(find.text('R\$ 900,00'), findsWidgets);
    expect(find.text('R\$ 45,00'), findsWidgets);
    expect(find.text('R\$ 100,00 / 10% ⚠'), findsOneWidget); // above the 5% limit
    await tapKey(tester, 'quote-save');
    final line = (f.body(f.last('POST', '/api/sales/quotes'))['lines'] as List).single as Map<String, dynamic>;
    expect(line['ipiPercent'], 5);
    expect(line['icmsPercent'], 18);
  });

  testWidgets('"Adicionar e novo" keeps the lead time and a repeated product is pointed out', (tester) async {
    final f = _fake();
    await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
    await _pickCustomer(tester);
    await _startItem(tester);
    await tester.enterText(find.byKey(const ValueKey('field-quantity')), '10');
    await tester.enterText(find.byKey(const ValueKey('field-leadTimeDays')), '15');
    await tester.tap(find.byKey(const ValueKey('form-save-new')));
    await tester.pumpAndSettle();
    // The next item opens on the product picker; its lead time starts as the last one.
    await tester.tap(find.text('TB-25 · Tubo 25,4 x 1,5').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('field-leadTimeDays'))).controller!.text, '15');
    await tester.enterText(find.byKey(const ValueKey('field-quantity')), '5');
    await _tapDialogButton(tester, 'Adicionar item');
    expect(find.text('Itens (2)'), findsOneWidget);
    expect(find.textContaining('já está na linha 1'), findsOneWidget);
  });

  testWidgets('an item needs a quantity above zero and a lead time in digits', (tester) async {
    final f = _fake();
    await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
    await _pickCustomer(tester);
    await _startItem(tester);
    await tester.enterText(find.byKey(const ValueKey('field-quantity')), '0');
    await tester.enterText(find.byKey(const ValueKey('field-leadTimeDays')), '1a5');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('field-leadTimeDays'))).controller!.text, '15');
    await _tapDialogButton(tester, 'Adicionar item');
    expect(find.text('Deve ser maior que zero'), findsOneWidget);
    expect(find.text('Itens (0)'), findsOneWidget);
  });

  testWidgets('an item can be duplicated and a removal can be undone', (tester) async {
    final f = _fake();
    await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
    await _pickCustomer(tester);
    await _startItem(tester);
    await tester.enterText(find.byKey(const ValueKey('field-quantity')), '10');
    await tester.enterText(find.byKey(const ValueKey('field-leadTimeDays')), '15');
    await _tapDialogButton(tester, 'Adicionar item');
    await tester.tap(find.byTooltip('Duplicar'));
    await tester.pumpAndSettle();
    expect(find.text('Itens (2)'), findsOneWidget);
    await tester.tap(find.byTooltip('Remover').last);
    await tester.pumpAndSettle();
    expect(find.text('Itens (1)'), findsOneWidget);
    await tapText(tester, 'Desfazer');
    expect(find.text('Itens (2)'), findsOneWidget);
  });

  testWidgets('saving without a customer shows the error on the field and Ctrl+S saves', (tester) async {
    final f = _fake();
    await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Informe o cliente'), findsOneWidget);
    expect(find.text('Inclua ao menos um item'), findsOneWidget);
    expect(f.called('POST', '/api/sales/quotes'), isFalse);
  });

  testWidgets('what was typed comes back after the session ends under the editor', (tester) async {
    final f = _fake();
    final session = await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
    await tester.enterText(find.widgetWithText(TextField, 'Observações'), 'Entregar na doca 3');
    DraftRegistry.saveAll();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: QuoteEditorScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rascunho recuperado: nada foi salvo ainda.'), findsOneWidget);
    expect(find.text('Entregar na doca 3'), findsOneWidget);
  });

  testWidgets('validity takes digits only and says until when it holds', (tester) async {
    final f = _fake();
    await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s));
    expect(find.text('Vazio = padrão: 15 dias'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('quote-validity')), '3 dias');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('quote-validity'))).controller!.text, '3');
    expect(find.textContaining('Vale até'), findsOneWidget);
  });

  testWidgets('a quote opened for a customer starts with that customer and its prazo', (tester) async {
    final f = _fake();
    await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s, customer: (id: 2, name: 'BTS Tubos')));
    expect(find.text('BTS Tubos'), findsOneWidget);
    expect(f.called('GET', '/api/customers/2/addresses'), isTrue);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('add-line'))).onPressed, isNotNull);
  });

  testWidgets('changing the product of a line takes the old product taxes and description with it', (tester) async {
    List<Map<String, dynamic>>? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LinesEditor(
              api: ApiClient(baseUrl: 'http://api.test'),
              title: 'Itens',
              fields: const [FieldSpec('productId', 'Produto', type: FieldType.integer), FieldSpec('description', 'Descrição')],
              columns: [ColumnSpec('Produto', (e) => '${e['productId']}')],
              lines: const [
                {'productId': 1, 'ipiPercent': 5, 'icmsPercent': 18, 'description': 'Tubo velho'},
              ],
              staleOnChange: const {
                'productId': ['ipiPercent', 'icmsPercent', 'description'],
              },
              onChanged: (l) => changed = l,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-productId')), '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    final line = changed!.single;
    expect(line['productId'], 2);
    expect(line.containsKey('ipiPercent'), isFalse);
    expect(line.containsKey('icmsPercent'), isFalse);
    expect(line['description'], isNull);
  });

  testWidgets('an empty list offers to create the first quote, and a chosen situation switches "Somente abertas" off', (tester) async {
    final f = MoreFake();
    f.overrides['GET /api/sales/quotes'] = (r) => jsonResp(pageOf([]));
    await pumpMore(tester, f, (s) => QuotesScreen(session: s));
    expect(find.text('Nenhum orçamento aberto.'), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-new-quote')), findsOneWidget);
    expect(find.text('Limpar filtros'), findsNothing);
  });
  testWidgets('a sales order item is as short as a quote item: the measures come from the product', (tester) async {
    final f = _fake();
    await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s, asOrder: true));
    await _pickCustomer(tester);
    await _startItem(tester);
    for (final key in ['quantity', 'unitPrice', 'leadTimeDays', 'deliveryDate', 'description']) {
      expect(find.byKey(ValueKey('field-$key')), findsOneWidget, reason: key);
    }
    for (final key in ['outsideDiameter', 'thickness', 'length', 'standard', 'condition', 'saleUnit', 'pieceWeightKg', 'materialNeedKg', 'toleranceDiameter', 'feasibilityId']) {
      expect(find.byKey(ValueKey('field-$key')), findsNothing, reason: key);
    }
    expect(find.text('Nova linha'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('field-unitPrice'))).controller!.text, '100,00'); // price from the customer's table, like the quote
  });
}
