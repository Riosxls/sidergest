import 'dart:typed_data';

import 'package:ebt_engenharia/screens/sales_common.dart';
import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:ebt_engenharia/widgets/pipeline.dart' show StagePath;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sales_more_support.dart';

MoreFake _fake(String status) {
  final f = MoreFake();
  f.quote['status'] = status;
  if (status == 'Sent') {
    f.quote
      ..['validUntil'] = '2099-01-01'
      ..['sentAt'] = '2026-10-26T12:00:00Z'
      ..['sentTo'] = 'compras@bts.com';
  }
  return f;
}

Future<void> _open(WidgetTester tester, MoreFake f, {String role = 'Sales'}) async {
  await tester.pumpWidget(const SizedBox.shrink()); // a screen from an earlier call must not keep its state
  await pumpMore(tester, f, (s) => QuoteScreen(session: s, id: 5), role: role);
}

Map<String, dynamic> _row(int id, String reference, String status, {int? supersededById, String? supersededBy}) => {
  'id': id,
  'reference': reference,
  'customerName': 'BTS Tubos',
  'status': status,
  'revision': 0,
  'total': 1000,
  'validUntil': null,
  'createdAt': '2026-10-25T12:00:00Z',
  'createdBy': 'ana',
  'needsApproval': false,
  'followUp': false,
  'expiring': false,
  'supersededById': supersededById,
  'supersededBy': supersededBy,
};

void main() {
  group('purchase order in one dialog', () {
    testWidgets('written text: saved, then registered, then the print offer for the saved paper', (tester) async {
      final f = _fake('Accepted');
      await _open(tester, f);
      await tapKey(tester, 'quote-po-start-text');
      expect(find.text('Pedido de compra de PROP 31'), findsOneWidget);
      // One date field per item with our date as the hint, as in the old form.
      expect(find.textContaining('Nossa data:'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('po-text')), 'Pedido 77 do cliente');
      await tester.enterText(find.byKey(const ValueKey('po-number')), 'PO-77');
      await tester.enterText(find.byKey(const ValueKey('po-note')), 'urgente');
      await tapKey(tester, 'po-register');
      final put = f.log.indexWhere((r) => r.method == 'PUT' && r.url.path == '/api/sales/quotes/5/request');
      final post = f.log.indexWhere((r) => r.method == 'POST' && r.url.path == '/api/sales/quotes/5/purchase-order');
      expect(put, greaterThanOrEqualTo(0));
      expect(post, greaterThan(put), reason: 'the text is saved before the order is registered');
      final body = f.body(f.log[post]);
      expect(body['customerPo'], 'PO-77');
      expect(body['note'], 'urgente');
      expect(body['deliveryDates'], isEmpty, reason: 'our date was kept');
      expect(find.text('Pedido de compra registrado'), findsOneWidget);
      // The print offer comes after the success, not before.
      expect(find.text('Imprimir o pedido de compra do cliente?'), findsOneWidget);
    });

    testWidgets("a file is uploaded first, and the customer's own date is sent for the item", (tester) async {
      final f = _fake('Accepted');
      f.overrides['POST /api/sales/quotes/5/request-file'] = (r) {
        f.quote
          ..['requestFileName'] = 'pedido.pdf'
          ..['requestFileSize'] = 3;
        return jsonResp(f.quote);
      };
      final old = requestFilePicker;
      requestFilePicker = () async => (name: 'pedido.pdf', bytes: Uint8List.fromList([1, 2, 3]));
      addTearDown(() => requestFilePicker = old);
      await _open(tester, f);
      await tapKey(tester, 'quote-po-start');
      expect(find.text('Nenhum arquivo escolhido'), findsOneWidget);
      await tapKey(tester, 'po-pick-file');
      expect(find.text('pedido.pdf'), findsOneWidget);
      final date = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('po-date-'));
      await tester.enterText(date, '15/12/2030');
      await tapKey(tester, 'po-register');
      expect(f.called('POST', '/api/sales/quotes/5/request-file'), isTrue);
      final dates = f.body(f.last('POST', '/api/sales/quotes/5/purchase-order'))['deliveryDates'] as List;
      expect(dates.single['deliveryDate'], '2030-12-15');
      expect(find.text('Imprimir o pedido de compra do cliente?'), findsOneWidget);
    });

    testWidgets('nothing attached and no text is refused without calling the server', (tester) async {
      final f = _fake('Accepted');
      await _open(tester, f);
      await tapKey(tester, 'quote-po-start');
      await tapKey(tester, 'po-register');
      expect(find.byKey(const ValueKey('po-error')), findsOneWidget);
      expect(f.called('POST', '/api/sales/quotes/5/purchase-order'), isFalse);
      expect(f.called('PUT', '/api/sales/quotes/5/request'), isFalse);
    });

    testWidgets('an invalid date is pointed out on its field', (tester) async {
      final f = _fake('Accepted');
      await _open(tester, f);
      await tapKey(tester, 'quote-po-start-text');
      await tester.enterText(find.byKey(const ValueKey('po-text')), 'Pedido');
      final date = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('po-date-'));
      await tester.enterText(date, '99/99/2030');
      await tapKey(tester, 'po-register');
      expect(find.text('Data inválida (dd/mm/aaaa)'), findsOneWidget);
      expect(f.called('PUT', '/api/sales/quotes/5/request'), isFalse);
    });

    testWidgets('a registration that fails keeps the attachment and a retry does not upload it again', (tester) async {
      final f = _fake('Accepted');
      var failing = true;
      f.overrides['POST /api/sales/quotes/5/purchase-order'] = (r) {
        if (failing) return jsonResp({'title': 'Erro', 'detail': 'Data inválida'}, 409);
        f.quote['status'] = 'PurchaseOrder';
        return jsonResp(f.quote);
      };
      await _open(tester, f);
      await tapKey(tester, 'quote-po-start-text');
      await tester.enterText(find.byKey(const ValueKey('po-text')), 'Pedido 77');
      await tapKey(tester, 'po-register');
      expect(find.textContaining('Erro: Data inválida'), findsOneWidget);
      expect(find.textContaining('já está anexado'), findsOneWidget);
      expect(find.text('Pedido de compra de PROP 31'), findsOneWidget); // still open, nothing typed is lost
      failing = false;
      await tapKey(tester, 'po-register');
      expect(f.where('PUT', '/api/sales/quotes/5/request'), hasLength(1));
      expect(find.text('Pedido de compra registrado'), findsOneWidget);
    });

    testWidgets('closing after the attachment was saved says the registration is still pending', (tester) async {
      final f = _fake('Accepted');
      f.overrides['POST /api/sales/quotes/5/purchase-order'] = (r) => jsonResp({'title': 'Erro', 'detail': 'Falhou'}, 409);
      await _open(tester, f);
      await tapKey(tester, 'quote-po-start-text');
      await tester.enterText(find.byKey(const ValueKey('po-text')), 'Pedido 77');
      await tapKey(tester, 'po-register');
      await tapKey(tester, 'po-cancel');
      expect(find.textContaining('registro ainda está pendente'), findsOneWidget);
      expect(find.text('Pedido de compra anexado · registre-o'), findsOneWidget);
    });

    testWidgets('cancelling the form of an attached order says the registration is still pending', (tester) async {
      final f = _fake('Accepted');
      f.quote['requestFileName'] = 'pedido.pdf';
      await _open(tester, f);
      await tapKey(tester, 'quote-po');
      await skipGate(tester);
      await tapText(tester, 'Cancelar');
      expect(find.textContaining('registro ainda está pendente'), findsOneWidget);
    });
  });

  group('quote list', () {
    testWidgets('"Limpar filtros" brings back "Somente abertas", which counts as a filter when turned off', (tester) async {
      final f = _fake('Draft');
      f.overrides['GET /api/sales/quotes'] = (r) => jsonResp(pageOf([]));
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      expect(find.text('Nenhum orçamento aberto.'), findsOneWidget);
      expect(find.text('Limpar filtros'), findsNothing);
      await tapText(tester, 'Somente abertas');
      expect(f.log.last.url.queryParameters.containsKey('open'), isFalse);
      expect(find.text('Nada encontrado com a busca e os filtros atuais'), findsOneWidget);
      await tapText(tester, 'Limpar filtros');
      expect(f.log.last.url.queryParameters['open'], 'true');
      expect(find.text('Nenhum orçamento aberto.'), findsOneWidget);
    });

    testWidgets('"Substituída" is a situation of its own and "Cancelada" leaves the replaced ones out', (tester) async {
      final f = _fake('Draft');
      f.overrides['GET /api/sales/quotes'] = (r) => jsonResp(
        pageOf([
          _row(1, 'PROP 1', 'Cancelled', supersededById: 8, supersededBy: 'PROP 1A'),
          _row(2, 'PROP 2', 'Cancelled'),
        ]),
      );
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      await tester.tap(find.byKey(const ValueKey('filter-Situação')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Substituída').last);
      await tester.pumpAndSettle();
      expect(f.log.last.url.queryParameters['status'], 'Cancelled');
      expect(find.text('PROP 1'), findsOneWidget);
      expect(find.text('PROP 2'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('filter-Situação')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelada').last);
      await tester.pumpAndSettle();
      expect(f.log.last.url.queryParameters['status'], 'Cancelled');
      expect(find.text('PROP 1'), findsNothing);
      expect(find.text('PROP 2'), findsOneWidget);
    });

    testWidgets('cancelling from the row menu reloads the list', (tester) async {
      final f = _fake('Draft');
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancelar');
      await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'Engano');
      final before = f.where('GET', '/api/sales/quotes').length;
      await tapText(tester, 'Confirmar');
      expect(f.where('GET', '/api/sales/quotes').length, greaterThan(before));
    });

    testWidgets('the line columns say what the value includes and keep up to four decimals of a unit price', (tester) async {
      expect(fmtUnitPrice(12.5), 'R\$ 12,50');
      expect(fmtUnitPrice(12.3456), 'R\$ 12,3456');
      expect(fmtUnitPrice(12.345), 'R\$ 12,345');
      expect(fmtUnitPrice(1234.5), 'R\$ 1.234,50');
      expect(fmtUnitPrice(null), '');
      expect(salesLineColumns.any((c) => c.label == 'Valor c/ impostos (estim.)'), isTrue);
      expect(salesLineColumns.any((c) => c.label == 'Valor estimado'), isFalse);
      final f = _fake('Sent');
      f.quote['lines'] = [
        {...(f.quote['lines'] as List).first as Map<String, dynamic>, 'unitPrice': 12.3456, 'quantity': 3, 'total': 37.04},
      ];
      await _open(tester, f);
      expect(find.text('R\$ 12,3456'), findsOneWidget);
    });
  });

  group('quote screen', () {
    testWidgets('the credit banner is for open quotes only and goes away when the quote is cancelled', (tester) async {
      final f = _fake('Draft');
      f.credit = {'limit': 10000, 'open': 8000, 'thisOrder': 11400, 'exceeded': true, 'limitSource': 'customer'};
      await _open(tester, f);
      expect(find.byKey(const ValueKey('quote-credit-banner')), findsOneWidget);
      await openMenu(tester, 'quote-menu', 'Cancelar orçamento');
      await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'Engano');
      await tapText(tester, 'Confirmar');
      expect(find.text('Cancelada'), findsWidgets);
      expect(find.byKey(const ValueKey('quote-credit-banner')), findsNothing);
      // A lost quote opened later never shows it either, even if the server still says exceeded.
      final g = _fake('Rejected');
      g.credit = f.credit;
      await _open(tester, g);
      expect(find.byKey(const ValueKey('quote-credit-banner')), findsNothing);
    });

    testWidgets('deleting says the quote and its history are gone for good, not that a draft is', (tester) async {
      final f = _fake('Draft');
      await _open(tester, f);
      await openMenu(tester, 'quote-menu', 'Excluir');
      expect(find.text('O orçamento e o histórico dele somem de vez. Não dá para desfazer.'), findsOneWidget);
    });

    testWidgets('a viability analysis is asked for only while the quote is being worked', (tester) async {
      for (final status in ['Rejected', 'Expired', 'Cancelled', 'Converted']) {
        await _open(tester, _fake(status));
        await tester.tap(find.byKey(const ValueKey('quote-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Pedir análise de viabilidade'), findsNothing, reason: status);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
      await _open(tester, _fake('Sent'));
      await tester.tap(find.byKey(const ValueKey('quote-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Pedir análise de viabilidade'), findsOneWidget);
    });

    testWidgets('a conflict from the credit limit tells a salesperson to ask the commercial manager', (tester) async {
      final f = _fake('PurchaseOrder');
      f.overrides['POST /api/sales/quotes/5/convert'] = (_) => jsonResp({'title': 'Conflito', 'detail': 'Credit limit exceeded'}, 409);
      f.credit = {'limit': 10000, 'open': 8000, 'thisOrder': 11400, 'exceeded': true, 'limitSource': 'customer'};
      await _open(tester, f);
      await tapKey(tester, 'quote-convert');
      await tapKey(tester, 'confirm-step');
      expect(find.text('Limite de crédito excedido'), findsNothing);
      expect(find.textContaining('Peça a liberação ao gerente comercial'), findsOneWidget);
    });

    testWidgets('the path of a converted quote shows the sales order step as done', (tester) async {
      expect(quotePath('Converted'), (5, null));
      final f = _fake('Converted');
      f.quote
        ..['salesOrderId'] = 9
        ..['salesOrderReference'] = 'PV 9';
      await _open(tester, f);
      final path = tester.widget<StagePath>(find.byType(StagePath));
      expect(path.current, 5);
      expect(path.steps[path.current].label, 'Ordem de Produção');
      expect(find.byTooltip('Abrir: Pedido de venda'), findsOneWidget); // still the link to the order
    });
  });

  group('quote editor', () {
    testWidgets('a save that fails for any reason shows a readable message', (tester) async {
      final f = _fake('Draft');
      // A 200 with a body that is not JSON is not an ApiException.
      f.overrides['PUT /api/sales/quotes/5'] = (_) => jsonResp('not a quote object');
      await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s, quote: f.quote));
      await tapKey(tester, 'quote-save');
      expect(find.textContaining('Resposta inesperada do servidor'), findsOneWidget);
    });

    testWidgets('changing the customer refills IPI and ICMS from the new customer table and says so', (tester) async {
      final f = _fake('Draft');
      f.overrides['GET /api/customers'] = (_) => jsonResp(
        pageOf([
          {'id': 2, 'name': 'BTS Tubos'},
          {'id': 3, 'name': 'Alfa Tubos'},
        ]),
      );
      f.overrides['GET /api/customers/3'] = (_) => jsonResp({
        'id': 3,
        'name': 'Alfa Tubos',
        'company': {'paymentTermId': 1, 'paymentTermName': '28 DDL'},
      });
      f.overrides['GET /api/sales/price'] = (r) {
        final other = r.url.queryParameters['customerId'] == '3';
        return jsonResp({'productId': 7, 'unitPrice': 100, 'ipiPercent': other ? 7 : 5, 'icmsPercent': other ? 12 : 18});
      };
      await pumpMore(tester, f, (s) => QuoteEditorScreen(session: s, quote: f.quote));
      await tapKey(tester, 'quote-customer');
      await tester.tap(find.text('Alfa Tubos').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Impostos (IPI e ICMS) dos itens atualizados'), findsOneWidget);
      // The notes (the prazo one is queued too) cover the save bar until they go away.
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).clearSnackBars();
      await tester.pumpAndSettle();
      await tapKey(tester, 'quote-save');
      final line = (f.body(f.last('PUT', '/api/sales/quotes/5'))['lines'] as List).single as Map<String, dynamic>;
      expect(line['ipiPercent'], 7);
      expect(line['icmsPercent'], 12);
    });
  });
}

Future<void> skipGate(WidgetTester tester) async {
  if (find.byKey(const ValueKey('gate-skip')).evaluate().isEmpty) return;
  await tester.tap(find.byKey(const ValueKey('gate-skip')));
  await tester.pumpAndSettle();
}
