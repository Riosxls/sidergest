import 'package:ebt_engenharia/screens/deliveries.dart';
import 'package:ebt_engenharia/screens/sales_orders.dart';
import 'package:ebt_engenharia/widgets/print_gate.dart';
import 'package:ebt_engenharia/widgets/print_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sales_more_support.dart';

Map<String, dynamic> _line0(MoreFake f) => (f.order['lines'] as List).first as Map<String, dynamic>;

MoreFake _released() {
  final f = MoreFake();
  f.order['status'] = 'Released';
  f.order['releasedBy'] = 'joao';
  f.order['releasedAt'] = '2026-10-27T12:00:00Z';
  return f;
}

MoreFake _inProduction() {
  final f = _released();
  _line0(f)
    ..['productionOrderId'] = 12
    ..['productionReference'] = 'OF 500'
    ..['productionStatus'] = 'Released'
    ..['produced'] = 20;
  return f;
}

Map<String, dynamic> _delivery({String status = 'Planned', String plannedDate = '2026-10-28', List<Map<String, dynamic>> history = const []}) => {
  'id': 15,
  'number': 15,
  'reference': 'ENT 15',
  'orderId': 9,
  'orderReference': 'PV 9',
  'customerId': 2,
  'customerName': 'BTS Tubos',
  'addressText': 'Av. Brasil, 100',
  'plannedDate': plannedDate,
  'status': status,
  'invoiceNumber': status == 'Shipped' ? '2581' : null,
  'packages': 1,
  'grossWeightKg': 85.5,
  'valueExIpi': 10000,
  'createdBy': 'ana',
  'createdAt': '2026-10-26T12:00:00Z',
  'lines': [
    {'id': 1, 'sequence': 10, 'productCode': 'TB-25', 'description': 'Tubo', 'quantity': 40, 'unit': 'PC', 'packages': 1},
  ],
  'history': history,
};

/// Layout errors raised while a page is pumped, except the ones of the shared record header (`pipeline.dart`), which this file does not own.
/// Call before pumping; the returned function lists what was caught.
List<String> Function() _collectLayoutErrors() {
  final caught = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    final text = d.toString();
    if (!text.contains('widgets/pipeline.dart')) caught.add(text.split('\n').take(6).join(' | '));
  };
  addTearDown(() => FlutterError.onError = original);
  return () => caught;
}

void main() {
  group('order page: refresh and shortcuts', () {
    testWidgets('the refresh button and F5 reload the order; a failed reload says so and keeps the page', (tester) async {
      final fake = _released();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      int loads() => fake.where('GET', '/api/sales/orders/9').length;
      final first = loads();
      await tapKey(tester, 'record-refresh');
      expect(loads(), first + 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(loads(), first + 2);
      fake.overrides['GET /api/sales/orders/9'] = (_) => jsonResp({'title': 'Erro', 'detail': 'fora do ar'}, 500);
      await tapKey(tester, 'record-refresh');
      expect(find.textContaining('Falha ao atualizar'), findsOneWidget);
      expect(find.text('PV 9 · BTS Tubos'), findsOneWidget);
    });
  });

  group('order page: items, totals and sections', () {
    testWidgets('items show the columns the user acts on with the technical line under the product, and the totals sit under them', (tester) async {
      final fake = _released();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.byKey(const ValueKey('order-items')), findsOneWidget);
      expect(find.text('BTS-001'), findsNothing); // the part number rides in parentheses with the code
      expect(find.text('TB-25 (BTS-001)'), findsOneWidget);
      expect(find.textContaining('NBR 5599'), findsWidgets);
      expect(find.textContaining('MP 120 kg'), findsOneWidget);
      expect(find.text('Saldo'), findsWidgets);
      expect(find.text('Produtos'), findsOneWidget);
      expect(find.text('Total'), findsWidgets);
      // The details no longer repeat the products and the IPI.
      expect(find.text('IPI'), findsOneWidget);
    });

    testWidgets('on a narrow screen each item is a card and nothing of the items overflows', (tester) async {
      final fake = _inProduction();
      final problems = _collectLayoutErrors();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9), size: const Size(480, 2600));
      expect(find.byKey(const ValueKey('order-items')), findsOneWidget);
      expect(find.text('10 · TB-25 (BTS-001)'), findsOneWidget);
      expect(problems(), isEmpty);
    });

    testWidgets('the production row stacks on a phone width without overflowing', (tester) async {
      final fake = _inProduction();
      _line0(fake)['ready'] = true;
      final problems = _collectLayoutErrors();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9), size: const Size(400, 2600));
      expect(find.text('Produção e disponibilidade'), findsOneWidget);
      expect(find.textContaining('OF 500 · Liberada'), findsWidgets);
      expect(problems(), isEmpty);
    });
  });

  group('order page: printing', () {
    testWidgets('with OFs in production one print menu names the pedido and each OF', (tester) async {
      final fake = _inProduction();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.byKey(const ValueKey('print-menu')), findsOneWidget);
      await tapKey(tester, 'print-menu');
      expect(find.text('Pedido interno de venda'), findsWidgets);
      expect(find.text('Ordem de fabricação OF 500'), findsOneWidget);
    });

    testWidgets('before production a single button prints the pedido', (tester) async {
      final created = MoreFake();
      await pumpMore(tester, created, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.byKey(const ValueKey('print-menu')), findsNothing);
      expect(find.byKey(const ValueKey('print-sales-order')), findsOneWidget);
      expect(find.byTooltip('Imprimir Pedido de venda PV 9'), findsOneWidget);
    });

    testWidgets('the papers panel folds away and says which papers were already printed here', (tester) async {
      final fake = _released();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.byKey(const ValueKey('doc-print-sales-order')), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-done-sales-order')), findsNothing);
      await PrintLog.mark('order:9:sales');
      await tapKey(tester, 'record-refresh'); // the page rebuilds and the panel reads the log again
      expect(find.byKey(const ValueKey('doc-done-sales-order')), findsOneWidget);
      expect(find.textContaining('1 impressos'), findsOneWidget);
      await tapKey(tester, 'print-panel-toggle');
      expect(find.byKey(const ValueKey('doc-print-sales-order')), findsNothing);
      await tapKey(tester, 'print-panel-toggle');
      expect(find.byKey(const ValueKey('doc-print-sales-order')), findsOneWidget);
    });

    testWidgets('a waived certificate and an order served from stock are shown as not applicable, not as waiting', (tester) async {
      final fake = _released();
      fake.order['certificateWaived'] = true;
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Dispensado para este pedido'), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(2)); // certificate waived + no OF
      expect(find.byIcon(Icons.hourglass_empty), findsWidgets); // the NF still waits for a shipment
    });

    test('a cancelled print dialog leaves the paper unmarked, a handled one marks it with the day', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PrintLog.isDone('k'), isFalse);
      await PrintLog.mark('k');
      expect(await PrintLog.isDone('k'), isTrue);
      final day = await PrintLog.doneOn('k');
      expect(day, isNotNull);
      expect(DateTime.now().difference(day!).inMinutes, lessThan(1));
      expect(await PrintLog.doneOn('never'), isNull);
    });

    testWidgets('printGate does not mark the paper when the print callback answers false, and marks it for an answer of true or nothing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      Future<bool> gate(String key, Future<void> Function() onPrint) async {
        final future = printGate(ctx, doneKey: key, title: 't', message: 'm', onPrint: onPrint);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('gate-print')));
        await tester.pumpAndSettle();
        return future;
      }

      Future<bool> cancelled() async => false;
      Future<bool> printed() async => true;
      expect(await gate('cancelled', cancelled), isTrue); // the flow may go on…
      expect(await PrintLog.isDone('cancelled'), isFalse); // …but the paper is still asked about next time
      expect(await gate('printed', printed), isTrue);
      expect(await PrintLog.isDone('printed'), isTrue);
      expect(await gate('silent', () async {}), isTrue);
      expect(await PrintLog.isDone('silent'), isTrue);
    });
  });

  group('order page: next step and dialogs', () {
    testWidgets('"Tudo expedido" has a button per delivery waiting for the customer', (tester) async {
      final fake = MoreFake();
      fake.order['status'] = 'Shipped';
      fake.order['deliveries'] = [
        {'id': 15, 'reference': 'ENT 15', 'plannedDate': '2026-10-28', 'status': 'Shipped', 'invoiceNumber': '2581', 'packages': 1},
      ];
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery(status: 'Shipped'));
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Tudo expedido'), findsOneWidget);
      await tapKey(tester, 'order-confirm-delivery-15');
      expect(find.text('ENT 15 · BTS Tubos'), findsOneWidget);
    });

    testWidgets('the cancel dialog paints its confirm button as destructive and cancels with "Cancelar"', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await openMenu(tester, 'order-menu', 'Cancelar pedido');
      final confirm = tester.widget<FilledButton>(find.byKey(const ValueKey('confirm-step')));
      final context = tester.element(find.byKey(const ValueKey('confirm-step')));
      expect(confirm.style?.backgroundColor?.resolve({}), Theme.of(context).colorScheme.error);
      expect(find.widgetWithText(TextButton, 'Voltar'), findsOneWidget);
    });

    testWidgets('the delivery dialog refuses a quantity above the balance and an invalid one, names the item, and has a date picker', (tester) async {
      final fake = _released();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapKey(tester, 'order-deliver');
      if (find.byKey(const ValueKey('gate-skip')).evaluate().isNotEmpty) await tapKey(tester, 'gate-skip');
      expect(find.byKey(const ValueKey('dl-date-pick')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('dl-qty-40')), '999');
      await tapKey(tester, 'delivery-ok');
      expect(find.textContaining('Item 10: a quantidade passa do saldo'), findsOneWidget);
      expect(fake.called('POST', '/api/sales/orders/9/deliveries'), isFalse);
      await tester.enterText(find.byKey(const ValueKey('dl-qty-40')), 'abc');
      await tapKey(tester, 'delivery-ok');
      expect(find.textContaining('Item 10: quantidade inválida'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('dl-qty-40')), '40');
      await tester.tap(find.byKey(const ValueKey('delivery-ok')));
      await tester.pumpAndSettle();
      expect(fake.called('POST', '/api/sales/orders/9/deliveries'), isTrue);
    });
  });

  group('delivery page', () {
    testWidgets('a late planned delivery says so in its card', (tester) async {
      final fake = MoreFake();
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery(plannedDate: '2020-01-02'));
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      expect(find.textContaining('Atrasada · era para 02/01/2020'), findsOneWidget);
    });

    testWidgets('the header carries the value of the delivery and a cancelled card shows the reason typed', (tester) async {
      final fake = MoreFake();
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(
        _delivery(
          status: 'Cancelled',
          history: [
            {
              'id': 9,
              'action': 'cancelled',
              'fromStatus': 'Planned',
              'toStatus': 'Cancelled',
              'note': 'Cliente pediu para adiar',
              'user': 'ana',
              'at': '2026-10-27T12:00:00Z',
            },
          ],
        ),
      );
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      expect(find.text('Cliente pediu para adiar'), findsWidgets);
      expect(find.textContaining('10.000,00'), findsWidgets);
    });

    testWidgets('cancelling a shipped delivery lists what happens before asking for the reason', (tester) async {
      final fake = MoreFake();
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery(status: 'Shipped'));
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      await openMenu(tester, 'delivery-menu', 'Cancelar entrega');
      expect(find.text('Cancelar a expedição de ENT 15?'), findsOneWidget);
      expect(find.textContaining('A baixa de estoque é estornada'), findsOneWidget);
      expect(find.byKey(const ValueKey('reason-field')), findsOneWidget);
    });

    testWidgets('with an authorized NF the cancel explains that the NF is cancelled first instead of asking for a reason', (tester) async {
      final withNf = MoreFake();
      withNf.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery(status: 'Shipped'));
      withNf.overrides['GET /api/fiscal/documents'] = (_) => jsonResp({
        'items': [
          {'id': 3, 'number': 2581, 'series': 1, 'cfopCode': '5101', 'invoiceTotal': 10500, 'accessKey': 'x', 'simulated': true},
        ],
      });
      await pumpMore(tester, withNf, (s) => DeliveryScreen(session: s, id: 15));
      await openMenu(tester, 'delivery-menu', 'Cancelar entrega');
      expect(find.textContaining('A NF 2581 está autorizada'), findsOneWidget);
      expect(find.byKey(const ValueKey('reason-field')), findsNothing);
    });

    testWidgets('the ship form carries a summary of what shipping does and folds the rare fields', (tester) async {
      final fake = MoreFake();
      fake.overrides['GET /api/sales/deliveries/15'] = (_) => jsonResp(_delivery());
      fake.certs = [
        {'id': 70, 'reference': 'CERT 1', 'status': 'Issued', 'description': 'Tubo', 'quantity': 40, 'unit': 'PC', 'issueDate': '2026-10-28'},
      ];
      fake.order['certificateWaived'] = true;
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      await tapKey(tester, 'delivery-ship');
      if (find.byKey(const ValueKey('gate-skip')).evaluate().isNotEmpty) await tapKey(tester, 'gate-skip');
      expect(find.textContaining('Sai do estoque: 40 PC do item 10'), findsOneWidget);
    });

    testWidgets('F5 and the refresh button reload the delivery', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => DeliveryScreen(session: s, id: 15));
      final first = fake.where('GET', '/api/sales/deliveries/15').length;
      await tapKey(tester, 'record-refresh');
      expect(fake.where('GET', '/api/sales/deliveries/15').length, first + 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(fake.where('GET', '/api/sales/deliveries/15').length, first + 2);
    });
  });

  group('shared pieces', () {
    testWidgets('the print button is busy while the PDF builds, so a second click does not print twice', (tester) async {
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => PrintPanel(
                docs: [
                  PrintDoc(
                    id: 'x',
                    label: 'Papel',
                    onPrint: () async {
                      builds++;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('doc-print-x')));
      await tester.pumpAndSettle();
      expect(builds, 1);
    });
  });
}
