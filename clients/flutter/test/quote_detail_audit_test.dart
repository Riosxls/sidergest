import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/screens/sales_common.dart';
import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:ebt_engenharia/widgets/pipeline.dart';
import 'package:ebt_engenharia/widgets/record_list.dart';
import 'package:ebt_engenharia/widgets/record_shortcuts.dart';
import 'package:ebt_engenharia/widgets/record_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sales_more_support.dart';

MoreFake _fake(String status) {
  final f = MoreFake();
  f.quote['status'] = status;
  if (status == 'Sent') {
    f.quote
      ..['validUntil'] = DateTime.now().add(const Duration(days: 8)).toIso8601String().substring(0, 10)
      ..['sentAt'] = '2026-10-26T12:00:00Z'
      ..['sentTo'] = 'outro@bts.com';
  }
  return f;
}

Future<void> _open(WidgetTester tester, MoreFake f, {String role = 'Sales', Size size = const Size(1700, 1800)}) async {
  // A fresh tree each time: the same screen type would keep the previous quote in its State.
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpMore(
    tester,
    f,
    (s) => QuoteScreen(session: s, id: 5),
    role: role,
    size: size,
  );
}

Widget _host(Widget child, {double width = 800}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);

void main() {
  group('shared helpers', () {
    test('statusLabel uses the wording of the record it is asked for', () {
      expect(statusLabel('Cancelled', kind: 'quote'), 'Cancelada');
      expect(statusLabel('Cancelled', kind: 'order'), 'Cancelado');
      expect(statusLabel('Shipped', kind: 'delivery'), 'Expedida');
      expect(statusLabel('Shipped', kind: 'order'), 'Expedido');
      expect(statusLabel('Sent'), 'Enviada ao cliente');
      expect(statusLabel(null), '');
    });

    test('the status vocabulary is one: Aprovada pelo cliente and Desconto autorizado', () {
      expect(statusLabel('Accepted'), 'Aprovada pelo cliente');
      expect(statusLabel('Approved'), 'Desconto autorizado');
    });

    test('the timeline shows the arrow only when the title does not already say where the record went', () {
      final history = [
        {'action': 'sent', 'fromStatus': 'Draft', 'toStatus': 'Sent', 'note': null, 'user': 'ana', 'at': '2026-10-25T12:00:00Z'},
        {'action': 'status', 'fromStatus': 'Created', 'toStatus': 'Released', 'note': null, 'user': 'ana', 'at': '2026-10-25T12:00:00Z'},
      ];
      final entries = timeline(history, kind: 'order');
      expect(entries[0].subtitle, '');
      expect(entries[1].subtitle, 'Criado → Liberado p/ produção');
    });

    test('quantities are grouped and lose trailing zeros', () {
      expect(fmtQty(12500), '12.500');
      expect(fmtQty(1500.5), '1.500,5');
      expect(fmtQty(0.25), '0,25');
      expect(fmtQty(null), fmt(null));
    });

    test('an order snapshot says where the order stands and what comes next', () {
      final created = orderSnapshot({'reference': 'PV 9', 'status': 'Created'});
      expect(created.title, 'PV 9 · Criado');
      expect(created.message, 'Falta liberar para a produção.');
      final running = orderSnapshot({'reference': 'PV 9', 'status': 'Released', 'progress': 0.4, 'ready': false});
      expect(running.message, 'Em produção, 40% pronto.');
      expect(running.tone, Tone.progress);
      expect(orderSnapshot({'reference': 'PV 9', 'status': 'Released', 'ready': true}).tone, Tone.success);
      expect(orderSnapshot({'reference': 'PV 9', 'status': 'Cancelled', 'statusReason': 'Cliente desistiu'}).tone, Tone.danger);
    });
  });

  group('shared widgets', () {
    testWidgets('a narrow StagePath keeps the step icons and says "Etapa n de N" under the bar', (tester) async {
      await tester.pumpWidget(_host(const StagePath(steps: flowSteps, current: 2), width: 400));
      expect(find.byKey(const ValueKey('path-caption')), findsOneWidget);
      expect(find.text('Etapa 3 de 8 · Aprovada pelo cliente'), findsOneWidget);
      expect(find.byIcon(Icons.send_outlined), findsOneWidget); // a finished step is its own icon, not a bare check
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('a wide StagePath has no caption', (tester) async {
      await tester.pumpWidget(_host(const StagePath(steps: flowSteps, current: 2), width: 1200));
      expect(find.byKey(const ValueKey('path-caption')), findsNothing);
      expect(find.byIcon(Icons.check), findsWidgets);
    });

    testWidgets('the last step of a finished record reads "Etapa 8 de 8"', (tester) async {
      await tester.pumpWidget(_host(const StagePath(steps: flowSteps, current: 8), width: 400));
      expect(find.textContaining('Etapa 8 de 8'), findsOneWidget);
    });

    testWidgets('SimpleTable follows the width it is given, not the window', (tester) async {
      tester.view.physicalSize = const Size(1700, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cols = [col('Item', 'a'), col('Produto', 'b'), col('Qtd.', 'c', numeric: true)];
      final rows = [
        {'a': 1, 'b': 'TB-25', 'c': 10},
      ];
      await tester.pumpWidget(_host(SimpleTable(columns: cols, rows: rows), width: 420));
      expect(find.byType(ListTile), findsOneWidget); // narrow card in a wide window: tiles
      await tester.pumpWidget(_host(SimpleTable(columns: cols, rows: rows), width: 900));
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('SimpleTable leaves out a column that is empty in every row, and says what an empty table means', (tester) async {
      final cols = [col('Item', 'a'), col('Desc. %', 'd', numeric: true), col('IPI %', 'i', numeric: true)];
      final rows = [
        {'a': 1, 'd': '—', 'i': 5},
        {'a': 2, 'd': '—', 'i': 0},
      ];
      await tester.pumpWidget(_host(SimpleTable(columns: cols, rows: rows, hideWhenEmpty: const {'Desc. %', 'IPI %'})));
      expect(find.text('Desc. %'), findsNothing);
      expect(find.text('IPI %'), findsOneWidget); // one row has IPI
      await tester.pumpWidget(_host(SimpleTable(columns: cols, rows: const [], emptyText: 'Nenhuma entrega programada.')));
      expect(find.text('Nenhuma entrega programada.'), findsOneWidget);
    });

    testWidgets('a Section is a heading and wraps its actions under the title when it is narrow', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const Section(title: 'Pedido de compra', actions: [Text('ação 1'), Text('ação 2')], child: Text('corpo')), width: 360));
      expect(tester.getSemantics(find.text('Pedido de compra')).flagsCollection.isHeader, isTrue);
      expect(tester.getTopLeft(find.text('ação 1')).dy, greaterThan(tester.getBottomLeft(find.text('Pedido de compra')).dy - 1));
      handle.dispose();
    });

    testWidgets('RecordHeader labels the amount and turns a named field into a link', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        _host(
          RecordHeader(
            icon: Icons.request_quote_outlined,
            kind: 'Orçamento',
            title: 'PROP 1',
            amount: 'R\$ 10,00',
            amountLabel: 'Total + IPI',
            fields: const [('Cliente', 'BTS'), ('Prazo', '28 DDL')],
            fieldLinks: {'Cliente': () => opened = true},
          ),
        ),
      );
      expect(find.text('Total + IPI'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('header-link-Cliente')));
      expect(opened, isTrue);
      expect(find.byKey(const ValueKey('header-link-Prazo')), findsNothing);
    });

    testWidgets('confirmStep cancels with "Cancelar" unless told otherwise', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(onPressed: () => ctx = c, child: const Text('x')),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      final first = confirmStep(ctx, title: 'T', message: 'M');
      await tester.pumpAndSettle();
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Voltar'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      expect(await first, isFalse);
      await tester.pumpAndSettle();
      final second = confirmStep(ctx, title: 'T', message: 'M', cancelLabel: 'Manter como está');
      await tester.pumpAndSettle();
      expect(find.text('Manter como está'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-step')));
      expect(await second, isTrue);
    });

    testWidgets('RecordShortcuts: F5 refreshes and Ctrl+P prints', (tester) async {
      var refreshed = 0, printed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordShortcuts(
            onRefresh: () => refreshed++,
            onPrint: () => printed++,
            child: const Scaffold(body: Text('pagina')),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      expect(refreshed, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(printed, 1);
    });
  });

  group('quote page', () {
    testWidgets('while it loads the page shows the shape of the page, not a bare spinner', (tester) async {
      final f = _fake('Sent');
      f.overrides['GET /api/sales/quotes/5'] = (_) => throw StateError('never answered in this test');
      // The loading state is what is on screen before the first answer: pump without settling.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecordSkeleton())));
      expect(find.byKey(const ValueKey('record-skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the header total says what it adds up and the customer opens its page', (tester) async {
      await _open(tester, _fake('Sent'));
      expect(find.text('Total do orçamento'), findsOneWidget);
      expect(find.byKey(const ValueKey('header-link-Cliente')), findsOneWidget);
      expect(find.text('Orçamento PROP 31'), findsOneWidget);
    });

    testWidgets('contact, validity and freight are in the header while the quote is worked, and move to Detalhes afterwards', (tester) async {
      await _open(tester, _fake('Sent'));
      for (final label in ['Contato', 'Validade', 'Frete']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      final f = _fake('Converted');
      f.quote
        ..['salesOrderId'] = 9
        ..['salesOrderReference'] = 'PV 9'
        ..['validUntil'] = '2026-11-18'
        ..['decidedAt'] = '2026-11-03T12:00:00Z';
      await _open(tester, f);
      // Each is still shown once (in Detalhes) so nothing is lost.
      for (final label in ['Contato', 'Validade', 'Frete']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      final header = tester.getTopLeft(find.byKey(const ValueKey('header-link-Cliente'))).dy;
      expect(tester.getTopLeft(find.text('Frete')).dy, greaterThan(header + 200));
    });

    testWidgets('Desc. % and IPI % columns appear only when a line has something in them', (tester) async {
      final f = _fake('Sent');
      f.quote['lines'] = [
        {...(f.quote['lines'] as List).first as Map<String, dynamic>, 'ipiPercent': 0, 'discountPercent': 0},
      ];
      await _open(tester, f);
      expect(find.text('Desc. %'), findsNothing);
      expect(find.text('IPI %'), findsNothing);
      final g = _fake('Sent');
      g.quote['lines'] = [
        {...(g.quote['lines'] as List).first as Map<String, dynamic>, 'discountPercent': 12},
      ];
      await _open(tester, g);
      expect(find.text('Desc. %'), findsOneWidget);
      expect(find.text('⚠ 12'), findsOneWidget); // above the 5% limit of the fake
      expect(find.byKey(const ValueKey('quote-discount-note')), findsOneWidget);
    });

    testWidgets('the converted card says where the order stands', (tester) async {
      final f = _fake('Converted');
      f.quote
        ..['salesOrderId'] = 9
        ..['salesOrderReference'] = 'PV 9';
      await _open(tester, f);
      expect(f.called('GET', '/api/sales/orders/9'), isTrue);
      expect(find.textContaining('Este orçamento virou o pedido PV 9 · Criado. Falta liberar para a produção.'), findsOneWidget);
    });

    testWidgets('registering the send is named as such, and the PDF is one click away', (tester) async {
      await _open(tester, _fake('Draft'));
      expect(find.text('Registrar envio ao cliente'), findsOneWidget);
      expect(find.text('Enviar ao cliente'), findsNothing);
      // Document actions live only in the app bar menu, not on the status card.
      expect(find.byKey(const ValueKey('quote-pdf')), findsNothing);
      await _open(tester, _fake('Sent'));
      await tester.tap(find.byKey(const ValueKey('quote-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quote-menu-pdf')), findsOneWidget);
      expect(find.byKey(const ValueKey('quote-menu-mail')), findsOneWidget);
    });

    testWidgets('the menu offers Baixar PDF and shows the destructive entries in the error colour', (tester) async {
      await _open(tester, _fake('Draft'));
      await tester.tap(find.byKey(const ValueKey('quote-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Baixar PDF'), findsWidgets);
      final cancel = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Cancelar orçamento'));
      expect(cancel.textColor, isNotNull);
    });

    testWidgets('F5 and the refresh button reload the quote; a failed reload keeps the page and says so', (tester) async {
      final f = _fake('Sent');
      var gets = 0;
      var fail = false;
      f.overrides['GET /api/sales/quotes/5'] = (_) {
        gets++;
        return fail ? jsonResp({'title': 'Erro', 'detail': 'Servidor fora do ar'}, 500) : jsonResp(f.quote);
      };
      await _open(tester, f);
      final first = gets;
      await tester.tap(find.byKey(const ValueKey('quote-refresh')));
      await tester.pumpAndSettle();
      expect(gets, first + 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(gets, first + 2);
      fail = true;
      await tester.tap(find.byKey(const ValueKey('quote-refresh')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Falha ao atualizar'), findsOneWidget);
      expect(find.text('Aguardando resposta do cliente'), findsOneWidget);
    });

    testWidgets('a 409 that is not the credit limit does not offer to release it', (tester) async {
      final f = _fake('PurchaseOrder');
      f.overrides['POST /api/sales/quotes/5/convert'] = (_) => jsonResp({'title': 'Conflito', 'detail': 'Credit limit exceeded'}, 409);
      // The words of the message say "credit limit", but the server answers that the limit is fine: no override dialog.
      f.credit = {'limit': 10000, 'open': 0, 'thisOrder': 100, 'exceeded': false};
      await _open(tester, f, role: 'SalesManager');
      await tapKey(tester, 'quote-convert');
      await tapKey(tester, 'confirm-step');
      expect(find.text('Limite de crédito excedido'), findsNothing);
      expect(f.called('GET', '/api/sales/quotes/5/credit'), isTrue);
    });

    testWidgets('on a phone the history comes after the main column and the path shows its caption', (tester) async {
      await _open(tester, _fake('Sent'), size: const Size(400, 2400));
      expect(find.byKey(const ValueKey('path-caption')), findsOneWidget);
      expect(find.text('Histórico', skipOffstage: false), findsOneWidget);
    });
  });
}
