import 'package:ebt_engenharia/screens/sales_pipeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sales_more_support.dart';

Map<String, dynamic> _card(String kind, int id, String reference, String status, {List<String> badges = const [], String? date}) => {
  'kind': kind,
  'id': id,
  'reference': reference,
  'customerId': 2,
  'customerName': 'BTS Tubos',
  'value': 11400,
  'status': status,
  'date': date ?? '2026-11-10',
  'progress': null,
  'badges': badges,
};

Map<String, dynamic> _pipeline(Map<String, List<Map<String, dynamic>>> cards, {int openQuotes = 1, int openOrders = 2}) => {
  'kpis': {
    'openQuotesValue': 11400,
    'openQuotes': openQuotes,
    'winRate': 0.5,
    'openOrdersValue': 10500,
    'openOrders': openOrders,
    'lateOrders': 0,
    'readyToShip': 0,
    'pendingApprovals': 0,
  },
  'stages': [
    for (final k in ['quote', 'sent', 'accepted', 'po', 'order', 'production', 'ready', 'shipped', 'delivered'])
      {'key': k, 'count': (cards[k] ?? []).length, 'value': 0, 'cards': cards[k] ?? <Map<String, dynamic>>[]},
  ],
};

MoreFake _fake(Map<String, List<Map<String, dynamic>>> cards, {bool mail = false, int openQuotes = 1, int openOrders = 2}) {
  final f = MoreFake();
  f.overrides['GET /api/sales/pipeline'] = (_) => jsonResp(_pipeline(cards, openQuotes: openQuotes, openOrders: openOrders));
  f.overrides['GET /api/system/mail'] = (_) => jsonResp({'enabled': mail, 'from': mail ? 'orcamentos@ebt.com.br' : null});
  return f;
}

Future<void> _open(WidgetTester tester, MoreFake f, {String role = 'Sales'}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpMore(tester, f, (s) => SalesPipelineScreen(session: s), role: role);
}

void main() {
  group('sending a quote from the pipeline', () {
    final draft = {
      'quote': [_card('Quote', 5, 'PROP 31', 'Draft')],
    };

    testWidgets('with the system mail on, the card opens the quote (and its e-mail dialog) instead of only registering a send', (tester) async {
      final f = _fake(draft, mail: true);
      await _open(tester, f);
      await tapKey(tester, 'advance-Quote-5');
      expect(find.byKey(const ValueKey('quote-email')), findsOneWidget);
      expect(f.called('POST', '/api/sales/quotes/5/send'), isFalse);
    });

    testWidgets('with the mail off it says plainly that it only registers the send', (tester) async {
      final f = _fake(draft);
      await _open(tester, f);
      await tapKey(tester, 'advance-Quote-5');
      expect(find.text('Registrar envio de PROP 31?'), findsOneWidget);
      expect(find.textContaining('O sistema não envia e-mail'), findsOneWidget);
      await tapKey(tester, 'confirm-step');
      expect(f.called('POST', '/api/sales/quotes/5/send'), isTrue);
      expect(find.text('Envio registrado (o sistema não envia e-mail)'), findsOneWidget);
    });
  });

  group('converting from the pipeline', () {
    final po = {
      'po': [_card('Quote', 5, 'PROP 31', 'PurchaseOrder')],
    };

    void creditConflict(MoreFake f) {
      f.overrides['POST /api/sales/quotes/5/convert'] = (r) {
        if (f.body(r)['overrideCredit'] == true) return jsonResp(f.order, 201);
        return jsonResp({'title': 'Conflito', 'detail': 'Credit limit exceeded'}, 409);
      };
      f.credit = {'limit': 10000, 'open': 8000, 'thisOrder': 11400, 'exceeded': true, 'limitSource': 'customer'};
    }

    testWidgets('a salesperson refused by the credit limit is told to ask the commercial manager', (tester) async {
      final f = _fake(po);
      creditConflict(f);
      await _open(tester, f);
      await tapKey(tester, 'advance-Quote-5');
      await tapKey(tester, 'confirm-step');
      expect(find.textContaining('Peça a liberação ao gerente comercial'), findsOneWidget);
      expect(f.where('POST', '/api/sales/quotes/5/convert').length, 1);
    });

    testWidgets('a manager is offered the override, as on the quote screen', (tester) async {
      final f = _fake(po);
      creditConflict(f);
      await _open(tester, f, role: 'SalesManager');
      await tapKey(tester, 'advance-Quote-5');
      await tapKey(tester, 'confirm-step');
      expect(find.text('Limite de crédito excedido'), findsOneWidget);
      await tapKey(tester, 'confirm-step');
      expect(f.body(f.last('POST', '/api/sales/quotes/5/convert'))['overrideCredit'], isTrue);
      expect(find.text('Pedido PV 9 criado'), findsOneWidget);
    });
  });

  group('the board', () {
    testWidgets('captions say "1 orçamento" and "2 pedidos"', (tester) async {
      await _open(tester, _fake({}));
      expect(find.text('1 orçamento'), findsOneWidget);
      expect(find.text('2 pedidos'), findsOneWidget);
    });

    testWidgets('quote badges use the wording of the list, in the same tone', (tester) async {
      final f = _fake({
        'quote': [_card('Quote', 5, 'PROP 31', 'Draft', badges: ['discount'])],
        'sent': [_card('Quote', 6, 'PROP 32', 'Sent', badges: ['expiring', 'followup'])],
      });
      await _open(tester, f);
      expect(find.text('Desconto acima do limite'), findsOneWidget);
      expect(find.text('Vence em breve'), findsOneWidget);
      expect(find.text('Cobrar resposta'), findsOneWidget);
    });

    testWidgets('a reader gets no arrow, no drag hint and no new-quote button', (tester) async {
      final f = _fake({
        'quote': [_card('Quote', 5, 'PROP 31', 'Draft')],
        'order': [_card('Order', 9, 'PV 9', 'Created')],
      });
      await _open(tester, f, role: 'Reader');
      expect(find.byKey(const ValueKey('advance-Quote-5')), findsNothing);
      expect(find.byKey(const ValueKey('advance-Order-9')), findsNothing);
      expect(find.textContaining('Arraste um cartão'), findsNothing);
      expect(find.textContaining('Segure um cartão'), findsNothing);
      await _open(tester, f);
      expect(find.byKey(const ValueKey('advance-Quote-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('advance-Order-9')), findsOneWidget);
    });

    testWidgets('a role that may sell but not release sees the arrow only on the stages it can move', (tester) async {
      final f = _fake({
        'quote': [_card('Quote', 5, 'PROP 31', 'Draft')],
        'order': [_card('Order', 9, 'PV 9', 'Created')],
      });
      await _open(tester, f, role: 'Engineering');
      expect(find.byKey(const ValueKey('advance-Quote-5')), findsNothing);
    });

    testWidgets('a chip per stage shows its count and brings the column into view', (tester) async {
      final f = _fake({
        'sent': [_card('Quote', 6, 'PROP 32', 'Sent')],
        'delivered': [_card('Order', 9, 'PV 9', 'Delivered')],
      });
      await _open(tester, f);
      expect(find.text('Enviada · 1'), findsOneWidget);
      final scroll = tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('kanban')), matching: find.byType(Scrollable)).first);
      expect(scroll.position.pixels, 0);
      // The chips scroll too (the last one may start off screen).
      await tester.drag(find.byKey(const ValueKey('stage-chips')), const Offset(-2000, 0));
      await tester.pumpAndSettle();
      await tapKey(tester, 'stage-chip-delivered');
      expect(scroll.position.pixels, greaterThan(0));
    });

    testWidgets('the mouse wheel over the board moves the columns sideways', (tester) async {
      await _open(tester, _fake({}));
      final scroll = tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('kanban')), matching: find.byType(Scrollable)).first);
      expect(scroll.position.pixels, 0);
      // Over the header of a column (nothing there scrolls up and down).
      final at = tester.getCenter(find.byKey(const ValueKey('stage-quote'))) - const Offset(0, 250);
      final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(at);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
      await tester.pump();
      expect(scroll.position.pixels, greaterThan(0));
    });
  });
}
