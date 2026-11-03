import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'role_permissions.dart';
import 'sales_more_support.dart';

String _day(int offset) => DateTime.now().add(Duration(days: offset)).toIso8601String().substring(0, 10);

MoreFake _fake(String status, {void Function(MoreFake f)? tweak}) {
  final f = MoreFake();
  f.quote['status'] = status;
  if (status == 'Sent') {
    f.quote
      ..['validUntil'] = _day(8)
      ..['sentAt'] = '2026-10-26T12:00:00Z'
      ..['sentTo'] = 'outro@bts.com';
  }
  tweak?.call(f);
  return f;
}

Future<void> _openQuote(WidgetTester tester, MoreFake f, {String role = 'Sales'}) => pumpMore(tester, f, (s) => QuoteScreen(session: s, id: 5), role: role);

Future<void> _pick(WidgetTester tester, Finder field, String option) async {
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _saveForm(WidgetTester tester) async {
  // The line form of a quote says "Adicionar item": nothing is stored until the page is saved.
  // The line form says "Concluir" when it edits an item and "Adicionar item" when it adds one.
  final done = find.text('Concluir');
  final add = find.text('Adicionar item');
  await tester.tap((done.evaluate().isNotEmpty ? done : (add.evaluate().isNotEmpty ? add : find.text('Salvar'))).last);
  await tester.pumpAndSettle();
}

void main() {
  group('helpers', () {
    test('line estimate and parts add IPI and ICMS on the base value', () {
      final l = {'quantity': 10, 'unitPrice': 100, 'ipiPercent': 5, 'icmsPercent': 18};
      expect(lineEstimate(l), 1230);
      final parts = estimateParts([l, {'quantity': 'x'}]);
      expect(parts.products, 1000);
      expect(parts.ipi, 50);
      expect(parts.icms, 180);
      expect(lineEstimate({}), 0);
    });

    test('packSpec moves the technical keys under spec and leaves plain lines alone', () {
      final out = packSpec({'productId': 1, 'outsideDiameter': 25.4, 'standard': 'NBR', 'thickness': null});
      expect(out, {
        'productId': 1,
        'spec': {'outsideDiameter': 25.4, 'standard': 'NBR'},
      });
      expect(packSpec({'productId': 1}), {'productId': 1});
    });

    test('quoteAlert lists every alert, most urgent first', () {
      expect(quoteAlert({'status': 'PendingApproval'}), 'Acima do limite');
      expect(quoteAlert({'status': 'Draft', 'needsApproval': true}), 'Acima do limite');
      expect(quoteAlert({'status': 'Sent', 'followUp': true, 'expiring': true}), 'Cobrar resposta · Vence em breve');
      expect(quoteAlert({'status': 'Sent', 'expiring': true}), 'Vence em breve');
      expect(quoteAlert({'status': 'Sent'}), '');
    });

    test('who may delete a quote', () {
      final sales = Session(api: ApiClient(baseUrl: 'http://x'))..role = 'Sales'..permissions = rolePermissions['Sales']!;
      final admin = Session(api: ApiClient(baseUrl: 'http://x'))..role = 'Admin'..permissions = rolePermissions['Admin']!;
      expect(canDeleteQuote(sales, 'Draft', 0), isTrue);
      expect(canDeleteQuote(sales, 'Draft', 1), isFalse);
      expect(canDeleteQuote(sales, 'Cancelled', 0), isFalse);
      expect(canDeleteQuote(admin, 'Draft', 2), isTrue);
      expect(canDeleteQuote(admin, 'Rejected', 1), isTrue);
      expect(canDeleteQuote(admin, 'Sent', 0), isFalse);
    });
  });

  group('quote list', () {
    testWidgets('filters by mine, follow-up and expiring and clears them all', (tester) async {
      final f = _fake('Draft');
      f.quote['needsApproval'] = true;
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      expect(find.text('Acima do limite'), findsOneWidget);
      await tapKey(tester, 'filter-mine');
      expect(f.log.last.url.queryParameters['mine'], 'true');
      await tapKey(tester, 'filter-follow-up');
      expect(f.log.last.url.queryParameters['followUp'], 'true');
      await tapKey(tester, 'filter-expiring');
      expect(f.log.last.url.queryParameters['expiring'], 'true');
      await tapText(tester, 'Somente abertas');
      expect(f.log.last.url.queryParameters.containsKey('open'), isFalse);
    });

    testWidgets('row menu duplicates the quote and opens the copy', (tester) async {
      final f = _fake('Draft');
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Duplicar');
      expect(f.called('POST', '/api/sales/quotes/5/duplicate'), isTrue);
      expect(f.called('GET', '/api/sales/quotes/6'), isTrue);
      expect(find.text('Orçamento PROP 31A'), findsOneWidget);
    });

    testWidgets('row menu cancels a draft with a reason', (tester) async {
      final f = _fake('Draft');
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancelar');
      expect(find.text('Cancelar PROP 31'), findsOneWidget);
      await tapText(tester, 'Confirmar');
      expect(find.text('Obrigatório'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'Emitido por engano');
      await tapText(tester, 'Confirmar');
      expect(f.body(f.last('POST', '/api/sales/quotes/5/cancel')), {'note': 'Emitido por engano'});
      expect(find.text('PROP 31 cancelado'), findsOneWidget);
    });

    testWidgets('row menu deletes a new draft after confirming, and backing out keeps it', (tester) async {
      final f = _fake('Draft');
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Excluir');
      expect(find.text('Excluir PROP 31?'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(f.called('DELETE', '/api/sales/quotes/5'), isFalse);
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Excluir');
      await tapKey(tester, 'confirm-step');
      expect(f.called('DELETE', '/api/sales/quotes/5'), isTrue);
      expect(find.text('PROP 31 excluído'), findsOneWidget);
    });

    testWidgets('a sent quote offers only duplicate and a reader has no row menu nor new button', (tester) async {
      final f = _fake('Sent');
      await pumpMore(tester, f, (s) => QuotesScreen(session: s), size: const Size(2600, 1800));
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      expect(find.text('Duplicar'), findsOneWidget);
      expect(find.text('Cancelar'), findsNothing);
      expect(find.text('Excluir'), findsNothing);
      expect(find.text('Imprimir'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      final f2 = _fake('Draft');
      await pumpMore(tester, f2, (s) => QuotesScreen(session: s), role: 'Reader', size: const Size(2600, 1800));
      // A reader can still print a quote, but not change one.
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      expect(find.text('Imprimir'), findsOneWidget);
      expect(find.text('Duplicar'), findsNothing);
      expect(find.text('Novo orçamento'), findsNothing);
    });

    testWidgets('a failed duplicate shows the API message', (tester) async {
      final f = _fake('Draft')..overrides['POST /api/sales/quotes/5/duplicate'] = ((_) => jsonResp({'title': 'Erro', 'detail': 'Cliente inativo'}, 409));
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Duplicar');
      expect(find.text('Erro: Cliente inativo'), findsOneWidget);
    });
  });

  group('quote editor', () {
    Future<void> openNew(WidgetTester tester, MoreFake f) async {
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      await tapText(tester, 'Novo orçamento');
      expect(find.text('Novo orçamento'), findsOneWidget);
    }

    Future<void> pickCustomer(WidgetTester tester) async {
      await tapKey(tester, 'quote-customer');
      await tester.tap(find.text('BTS Tubos').last);
      await tester.pumpAndSettle();
    }

    Future<void> addItem(WidgetTester tester, {String qty = '10', String price = '120', String days = '15'}) async {
      await tapKey(tester, 'add-line');
      await tester.pumpAndSettle();
      await tester.tap(find.text('TB-25 · Tubo 25,4 x 1,5').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), qty);
      await tester.enterText(find.byKey(const ValueKey('field-unitPrice')), price);
      await tester.enterText(find.byKey(const ValueKey('field-leadTimeDays')), days);
      await _saveForm(tester);
    }

    testWidgets('validates customer, prazo and items in order', (tester) async {
      final f = _fake('Draft');
      await openNew(tester, f);
      await tapKey(tester, 'quote-save');
      expect(find.text('Informe o cliente'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('add-line'))).onPressed, isNull);
      expect(find.text('Escolha o cliente e o prazo de pagamento para adicionar itens'), findsOneWidget);
      await pickCustomer(tester);
      await tapKey(tester, 'quote-save');
      expect(find.text('Inclua ao menos um item'), findsOneWidget); // the customer's default prazo was applied
      expect(f.called('POST', '/api/sales/quotes'), isFalse);
    });

    testWidgets('customer brings addresses, contact and prazo; saved quote opens', (tester) async {
      final f = _fake('Draft');
      await openNew(tester, f);
      await pickCustomer(tester);
      expect(f.called('GET', '/api/customers/2/addresses'), isTrue);
      expect(find.text('Edilto'), findsOneWidget);
      expect(find.text('compras@bts.com'), findsOneWidget);
      await _pick(tester, find.byType(DropdownButtonFormField<int?>), 'Rua B, 5, Cotia, SP');
      await _pick(tester, find.byType(DropdownButtonFormField<String>).first, 'FOB (frete do cliente)');
      await addItem(tester);
      expect(find.byKey(const ValueKey('quote-approval-banner')), findsNothing);
      expect(find.text('Produtos'), findsOneWidget);
      expect(find.text('R\$ 1.200,00'), findsWidgets);
      await tapKey(tester, 'quote-save');
      final b = f.body(f.last('POST', '/api/sales/quotes'));
      expect(b['customerId'], 2);
      expect(b['addressId'], 4);
      expect(b['paymentTermId'], 1);
      expect(b['customPaymentTerm'], isNull);
      expect(b['freight'], 'Fob');
      expect(b['contactName'], 'Marta'); // the contact follows the delivery address chosen, since none was typed
      final line = (b['lines'] as List).single as Map<String, dynamic>;
      expect(line['productId'], 7);
      expect(line['quantity'], 10);
      expect(line['unitPrice'], 120);
      expect(line['leadTimeDays'], 15);
      expect(find.text('Orçamento PROP 31'), findsOneWidget);
    });

    testWidgets('a custom prazo is sent instead of a prazo id and can be cleared', (tester) async {
      final f = _fake('Draft');
      await openNew(tester, f);
      await tapKey(tester, 'quote-customer');
      await tester.tap(find.text('BTS Tubos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quote-term-1')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'picker-create');
      await tester.enterText(find.byKey(const ValueKey('prazo-custom')), '45 dias');
      await tapText(tester, 'Usar neste orçamento');
      expect(find.byKey(const ValueKey('quote-custom-term')), findsOneWidget);
      expect(find.text('45 dias'), findsOneWidget);
      await addItem(tester);
      await tapKey(tester, 'quote-save');
      final b = f.body(f.last('POST', '/api/sales/quotes'));
      expect(b['paymentTermId'], isNull);
      expect(b['customPaymentTerm'], '45 dias');
    });

    testWidgets('a discount above the limit and an unlisted price warn before sending', (tester) async {
      final f = _fake('Draft');
      f.settings['offListNeedsApproval'] = true;
      await openNew(tester, f);
      await pickCustomer(tester);
      await addItem(tester, price: '80');
      expect(find.byKey(const ValueKey('quote-approval-banner')), findsOneWidget);
      expect(find.textContaining('O maior desconto sobre a tabela é 20%'), findsOneWidget);
      f.listPrice = 0;
      await tapKey(tester, 'add-line');
      await tester.pumpAndSettle();
      await tester.tap(find.text('TB-25 · Tubo 25,4 x 1,5').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '1');
      await tester.enterText(find.byKey(const ValueKey('field-unitPrice')), '5');
      await tester.enterText(find.byKey(const ValueKey('field-leadTimeDays')), '3');
      await _saveForm(tester);
      expect(find.byKey(const ValueKey('quote-approval-banner')), findsOneWidget);
    });

    testWidgets('an API error stays on the editor and leaving with changes asks to discard', (tester) async {
      final f = _fake('Draft')..overrides['POST /api/sales/quotes'] = ((_) => jsonResp({'title': 'Cliente', 'detail': 'bloqueado'}, 409));
      await openNew(tester, f);
      await pickCustomer(tester);
      await addItem(tester);
      await tapKey(tester, 'quote-save');
      expect(find.text('Cliente: bloqueado'), findsOneWidget);
      expect(find.text('Novo orçamento'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tapText(tester, 'Continuar editando');
      expect(find.byKey(const ValueKey('quote-save')), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tapText(tester, 'Descartar');
      expect(find.byKey(const ValueKey('quote-save')), findsNothing);
    });

    testWidgets('editing a draft loads its items and saves with PUT', (tester) async {
      final f = _fake('Draft');
      await _openQuote(tester, f);
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar PROP 31'), findsOneWidget);
      expect(find.text('TB-25 · Tubo 25,4 x 1,5'), findsOneWidget);
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '200');
      await _saveForm(tester);
      await tapKey(tester, 'quote-save');
      final b = f.body(f.last('PUT', '/api/sales/quotes/5'));
      expect((b['lines'] as List).single['quantity'], 200);
      expect(find.text('Orçamento PROP 31'), findsOneWidget);
    });

    testWidgets('removing every item blocks saving', (tester) async {
      final f = _fake('Draft');
      await _openQuote(tester, f);
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remover'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'quote-save');
      expect(find.text('Inclua ao menos um item'), findsOneWidget);
      expect(f.called('PUT', '/api/sales/quotes/5'), isFalse);
    });
  });

  group('sending and approval', () {
    testWidgets('send to the customer records the recipient and offers the mail program', (tester) async {
      final f = _fake('Draft');
      f.quoteAfter['send'] = 'Sent';
      f.overrides['POST /api/sales/quotes/5/send'] = (r) {
        f.quote
          ..['status'] = 'Sent'
          ..['validUntil'] = _day(15)
          ..['sentAt'] = '2026-10-26T12:00:00Z'
          ..['sentTo'] = 'compras@bts.com';
        return jsonResp(f.quote);
      };
      await _openQuote(tester, f);
      expect(find.text('Pronta para enviar?'), findsOneWidget);
      await tapKey(tester, 'quote-send');
      expect(find.text('Registrar envio de PROP 31 ao cliente'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-sentTo'))).controller!.text, 'compras@bts.com');
      await tester.enterText(find.byKey(const ValueKey('field-note')), 'Segue proposta');
      await _saveForm(tester);
      expect(f.body(f.last('POST', '/api/sales/quotes/5/send')), {'sentTo': 'compras@bts.com', 'note': 'Segue proposta'});
      expect(find.textContaining('Envio registrado'), findsOneWidget);
      expect(find.text('Aguardando resposta do cliente'), findsOneWidget);
      await tester.tap(find.widgetWithText(SnackBarAction, 'Abrir e-mail'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum programa de e-mail configurado neste computador'), findsOneWidget);
    });

    testWidgets('a discounted draft asks before going to the manager and can be backed out of', (tester) async {
      final f = _fake('Draft');
      f.quote['needsApproval'] = true;
      (f.quote['totals'] as Map<String, dynamic>)['maxDiscountPercent'] = 12;
      f.quoteAfter['send'] = 'PendingApproval';
      await _openQuote(tester, f);
      expect(find.text('Desconto acima do limite'), findsOneWidget);
      await tapKey(tester, 'quote-send');
      expect(find.text('Enviar para aprovação?'), findsOneWidget);
      expect(find.textContaining('O desconto deste orçamento (12%) passa do limite de 5%'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(f.called('POST', '/api/sales/quotes/5/send'), isFalse);
      await tapKey(tester, 'quote-send');
      await tapKey(tester, 'confirm-step');
      expect(f.called('POST', '/api/sales/quotes/5/send'), isTrue);
      expect(find.text('Enviada para aprovação do gerente'), findsOneWidget);
      expect(find.text('Aguardando aprovação do gerente'), findsOneWidget);
      expect(find.byKey(const ValueKey('quote-approve')), findsNothing); // a salesperson cannot approve
    });

    testWidgets('the manager approves the discount', (tester) async {
      final f = _fake('PendingApproval');
      f.quoteAfter['approve'] = 'Approved';
      (f.quote['totals'] as Map<String, dynamic>)['maxDiscountPercent'] = 12;
      await _openQuote(tester, f, role: 'SalesManager');
      await tapKey(tester, 'quote-approve');
      expect(f.called('POST', '/api/sales/quotes/5/approve'), isTrue);
      expect(find.text('Desconto aprovado'), findsWidgets);
      expect(find.byKey(const ValueKey('quote-send')), findsOneWidget);
    });

    testWidgets('the manager refuses the discount with a reason and the quote returns to draft', (tester) async {
      final f = _fake('PendingApproval');
      f.quote['history'] = [
        {'id': 5, 'action': 'approval-rejected', 'fromStatus': 'PendingApproval', 'toStatus': 'Draft', 'note': 'Desconto alto', 'user': 'gerente', 'at': '2026-10-27T12:00:00Z'},
        ...(f.quote['history'] as List),
      ];
      await _openQuote(tester, f, role: 'SalesManager');
      await tapKey(tester, 'quote-reject-approval');
      expect(find.text('Recusar desconto'), findsWidgets);
      await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'Desconto alto');
      await tapText(tester, 'Confirmar');
      expect(f.body(f.last('POST', '/api/sales/quotes/5/reject-approval')), {'note': 'Desconto alto'});
      expect(find.text('Orçamento voltou para rascunho'), findsOneWidget);
      expect(find.textContaining('O gerente recusou o desconto: Desconto alto'), findsOneWidget);
    });

    testWidgets('going back to draft from approved asks first', (tester) async {
      final f = _fake('Approved');
      f.quote
        ..['approvedBy'] = 'gerente'
        ..['approvedAt'] = '2026-10-27T12:00:00Z';
      await _openQuote(tester, f);
      expect(find.textContaining('Aprovado por gerente'), findsOneWidget);
      await tapKey(tester, 'quote-reopen');
      await tapText(tester, 'Manter como está');
      expect(f.called('POST', '/api/sales/quotes/5/reopen'), isFalse);
      await tapKey(tester, 'quote-reopen');
      await tapKey(tester, 'confirm-step');
      expect(f.called('POST', '/api/sales/quotes/5/reopen'), isTrue);
      expect(find.text('Orçamento voltou para rascunho'), findsOneWidget);
      expect(find.text('Pronta para enviar?'), findsOneWidget);
    });
  });

  group('customer answer', () {
    testWidgets('extending the validity posts the new date', (tester) async {
      final f = _fake('Sent');
      await _openQuote(tester, f);
      await tapKey(tester, 'quote-extend');
      expect(find.text('Prorrogar validade de PROP 31'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('field-validUntil')), '30/12/2026');
      await tester.enterText(find.byKey(const ValueKey('field-note')), 'Pediu mais prazo');
      await _saveForm(tester);
      expect(f.body(f.last('POST', '/api/sales/quotes/5/extend')), {'validUntil': '2026-12-30', 'note': 'Pediu mais prazo'});
      expect(find.textContaining('Validade até'), findsOneWidget);
    });

    testWidgets('a refusal posts the lost reason and shows the lost sale', (tester) async {
      final f = _fake('Sent');
      f.quote['lostReason'] = 'Price';
      await _openQuote(tester, f);
      await tapKey(tester, 'quote-decline');
      expect(find.text('Venda perdida: cliente recusou PROP 31'), findsOneWidget);
      await _pick(tester, find.byKey(const ValueKey('field-lostReason')), 'Preço');
      await tester.enterText(find.byKey(const ValueKey('field-note')), 'Concorrente mais barato');
      await _saveForm(tester);
      final b = f.body(f.last('POST', '/api/sales/quotes/5/decline'));
      expect(b['lostReason'], 'Price');
      expect(b['note'], 'Concorrente mais barato');
      expect(find.text('Venda perdida'), findsOneWidget);
      expect(find.text('Motivo da perda'), findsOneWidget);
    });

    testWidgets('a revision supersedes this version and opens the new draft', (tester) async {
      final f = _fake('Sent');
      await _openQuote(tester, f);
      await tapKey(tester, 'quote-change');
      await _pick(tester, find.byKey(const ValueKey('field-change')), 'Cliente pediu: preço');
      await tester.enterText(find.byKey(const ValueKey('field-note')), 'Baixar 5%');
      await _saveForm(tester);
      expect(f.body(f.last('POST', '/api/sales/quotes/5/revise')), {'note': 'Cliente pediu: preço: Baixar 5%', 'customerPo': null});
      expect(find.text('PROP 31 substituída · nova revisão PROP 31A em rascunho'), findsOneWidget);
      expect(f.called('GET', '/api/sales/quotes/8'), isTrue);
      expect(find.text('Orçamento PROP 31A'), findsOneWidget);
    });

    testWidgets('revision letter shows in the header of a revised quote', (tester) async {
      final f = _fake('Draft');
      f.quote['revision'] = 2;
      await _openQuote(tester, f);
      expect(find.text('Orçamento comercial · revisão C'), findsOneWidget);
    });

    testWidgets('the customer approval failure is reported', (tester) async {
      final f = _fake('Sent')..overrides['POST /api/sales/quotes/5/accept'] = ((_) => jsonResp({'title': 'Erro', 'detail': 'Validade vencida'}, 409));
      await _openQuote(tester, f);
      await tapKey(tester, 'quote-accept');
      await tapKey(tester, 'confirm-step');
      expect(find.text('Erro: Validade vencida'), findsOneWidget);
      expect(find.text('Aguardando resposta do cliente'), findsOneWidget);
    });

    testWidgets('mail button reports when no mail program exists', (tester) async {
      final f = _fake('Sent');
      await _openQuote(tester, f);
      await tester.tap(find.byKey(const ValueKey('quote-mail')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum programa de e-mail configurado neste computador'), findsOneWidget);
    });
  });

  group('purchase order and conversion', () {
    testWidgets('without an attachment the register step is not offered, text unlocks it', (tester) async {
      final f = _fake('Accepted');
      await _openQuote(tester, f);
      expect(find.byKey(const ValueKey('quote-po')), findsNothing);
      expect(find.text('Nenhum pedido de compra anexado (PDF, imagem ou texto)'), findsOneWidget);
      await tapKey(tester, 'quote-po-start-text');
      expect(find.text('Texto do pedido de compra'), findsWidgets);
      await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'Pedido 77 do cliente');
      await tapText(tester, 'Salvar');
      expect(f.body(f.last('PUT', '/api/sales/quotes/5/request')), {'text': 'Pedido 77 do cliente'});
      expect(find.text('Pedido de compra anexado · registre-o'), findsOneWidget);
      expect(find.text('Pedido 77 do cliente'), findsOneWidget);
    });

    testWidgets('an attached file can be removed and an unprintable one says so', (tester) async {
      final f = _fake('Accepted');
      f.quote
        ..['requestFileName'] = 'pedido.docx'
        ..['requestFileSize'] = 3000;
      await _openQuote(tester, f);
      expect(find.text('pedido.docx · 3 KB'), findsOneWidget);
      expect(find.text('Substituir arquivo'), findsOneWidget);
      await tapKey(tester, 'quote-po-print');
      expect(find.textContaining('Este tipo de arquivo não imprime daqui'), findsOneWidget);
      await tester.tap(find.byTooltip('Remover anexo'));
      await tester.pumpAndSettle();
      expect(f.called('DELETE', '/api/sales/quotes/5/request-file'), isTrue);
      expect(find.text('Nenhum pedido de compra anexado (PDF, imagem ou texto)'), findsOneWidget);
    });

    testWidgets('a large attachment shows its size in MB', (tester) async {
      final f = _fake('Accepted');
      f.quote
        ..['requestFileName'] = 'scan.png'
        ..['requestFileSize'] = 2621440;
      await _openQuote(tester, f);
      expect(find.text('scan.png · 2,5 MB'), findsOneWidget);
    });

    testWidgets('converting to a sales order asks first, then opens the order', (tester) async {
      final f = _fake('PurchaseOrder');
      f.quote['customerPo'] = 'PO-4521';
      await _openQuote(tester, f);
      expect(find.textContaining('pedido do cliente PO-4521'), findsOneWidget);
      await tapKey(tester, 'quote-convert');
      expect(find.text('Gerar pedido de venda?'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(f.called('POST', '/api/sales/quotes/5/convert'), isFalse);
      await tapKey(tester, 'quote-convert');
      await tapKey(tester, 'confirm-step');
      expect(f.called('POST', '/api/sales/quotes/5/convert'), isTrue);
      expect(find.text('Pedido PV 9 criado'), findsOneWidget);
      expect(find.text('PV 9 · BTS Tubos'), findsOneWidget);
    });

    testWidgets('credit conflict: a manager can release anyway, a salesperson only sees the message', (tester) async {
      var forced = false;
      final f = _fake('PurchaseOrder');
      f.overrides['POST /api/sales/quotes/5/convert'] = (r) {
        if (f.body(r)['overrideCredit'] == true) {
          forced = true;
          return jsonResp(f.order, 201);
        }
        return jsonResp({'title': 'Conflito', 'detail': 'Credit limit exceeded'}, 409);
      };
      // The override flow is offered when the server confirms the limit is exceeded, not by reading the conflict message.
      f.credit = {'limit': 10000, 'open': 8000, 'thisOrder': 11400, 'exceeded': true, 'limitSource': 'customer'};
      await _openQuote(tester, f, role: 'SalesManager');
      await tapKey(tester, 'quote-convert');
      await tapKey(tester, 'confirm-step');
      expect(find.text('Limite de crédito excedido'), findsOneWidget);
      expect(find.textContaining('Liberar mesmo assim?'), findsOneWidget);
      await tapKey(tester, 'confirm-step');
      expect(forced, isTrue);
      expect(find.text('PV 9 · BTS Tubos'), findsOneWidget);
    });

    testWidgets('credit conflict for a salesperson is only reported', (tester) async {
      final f = _fake('PurchaseOrder')..overrides['POST /api/sales/quotes/5/convert'] = ((_) => jsonResp({'title': 'Conflito', 'detail': 'Credit limit exceeded'}, 409));
      await _openQuote(tester, f);
      await tapKey(tester, 'quote-convert');
      await tapKey(tester, 'confirm-step');
      expect(find.text('Limite de crédito excedido'), findsNothing);
      expect(find.text('Conflito: Credit limit exceeded'), findsOneWidget);
    });

    testWidgets('a converted quote links to its order', (tester) async {
      final f = _fake('Converted');
      f.quote
        ..['salesOrderId'] = 9
        ..['salesOrderReference'] = 'PV 9';
      await _openQuote(tester, f);
      expect(find.textContaining('Este orçamento virou o pedido PV 9'), findsOneWidget);
      await tapKey(tester, 'quote-open-order');
      expect(find.text('PV 9 · BTS Tubos'), findsOneWidget);
    });

    testWidgets('the credit banner names who set the limit', (tester) async {
      final f = _fake('Sent');
      f.credit = {'limit': 10000, 'open': 8000, 'thisOrder': 11400, 'exceeded': true, 'limitSource': 'customer'};
      await _openQuote(tester, f);
      expect(find.textContaining('passam do limite de R\$ 10.000,00 do cliente'), findsOneWidget);
    });
  });

  group('menu', () {
    Future<void> menu(WidgetTester tester, String item) async {
      await tapKey(tester, 'quote-menu');
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('text preview shows the proposal and copies it', (tester) async {
      final f = _fake('Sent');
      f.quote['conditions'] = 'Pagamento em 28 dias';
      await _openQuote(tester, f);
      await menu(tester, 'Ver texto do orçamento');
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Orçamento PROP 31')), findsOneWidget);
      expect(find.textContaining('ORÇAMENTO COMERCIAL PROP 31', findRichText: true), findsOneWidget);
      expect(find.textContaining('Condições gerais: Pagamento em 28 dias', findRichText: true), findsOneWidget);
      await tapText(tester, 'Copiar');
      expect(find.text('Texto copiado'), findsOneWidget);
    });

    testWidgets('preview of a dated item and a quote without validity or contact', (tester) async {
      final f = _fake('Draft');
      f.quote
        ..['contactName'] = null
        ..['customerReference'] = null
        ..['conditions'] = null
        ..['paymentTermName'] = null
        ..['customPaymentTerm'] = '45 dias'
        ..['freight'] = 'Fob';
      ((f.quote['lines'] as List).first as Map<String, dynamic>)
        ..['deliveryDate'] = '2026-12-01'
        ..['customerPartNumber'] = null;
      await _openQuote(tester, f);
      await menu(tester, 'Ver texto do orçamento');
      expect(find.textContaining('Prazo: 45 dias', findRichText: true), findsOneWidget);
      expect(find.textContaining('01/12/2026', findRichText: true), findsWidgets);
      await tapText(tester, 'Fechar');
    });

    testWidgets('duplicate asks for an optional other customer and opens the copy', (tester) async {
      final f = _fake('Sent');
      await _openQuote(tester, f);
      await menu(tester, 'Duplicar');
      expect(find.text('Duplicar PROP 31'), findsOneWidget);
      await _saveForm(tester);
      expect(f.called('POST', '/api/sales/quotes/5/duplicate'), isTrue);
      expect(find.textContaining('criado como cópia de PROP 31'), findsOneWidget);
      expect(find.text('Orçamento PROP 31A'), findsOneWidget);
    });

    testWidgets('cancel from the menu needs a reason', (tester) async {
      final f = _fake('Draft');
      await _openQuote(tester, f);
      await menu(tester, 'Cancelar orçamento');
      expect(find.text('Cancelar PROP 31'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('prompt-text')), 'Engano');
      await tapText(tester, 'Confirmar');
      expect(f.body(f.last('POST', '/api/sales/quotes/5/cancel')), {'note': 'Engano'});
      expect(find.text('Orçamento cancelado'), findsOneWidget);
      expect(find.text('Cancelada'), findsWidgets);
    });

    testWidgets('delete from the menu closes the screen', (tester) async {
      final f = _fake('Draft');
      await pumpMore(tester, f, (s) => QuotesScreen(session: s));
      await tester.tap(find.text('PROP 31'));
      await tester.pumpAndSettle();
      await menu(tester, 'Excluir');
      expect(find.text('Excluir PROP 31?'), findsOneWidget);
      expect(find.text('O rascunho é apagado definitivamente.'), findsOneWidget);
      await tapKey(tester, 'confirm-step');
      expect(f.called('DELETE', '/api/sales/quotes/5'), isTrue);
      expect(find.text('Orçamento excluído'), findsOneWidget);
      expect(find.byType(QuotesScreen), findsOneWidget);
    });

    testWidgets('feasibility request opens the form with the quote filled in', (tester) async {
      final f = _fake('Draft');
      await _openQuote(tester, f);
      await menu(tester, 'Pedir análise de viabilidade');
      expect(find.text('Nova análise de viabilidade'), findsOneWidget);
    });

    testWidgets('a reader has no edit, duplicate or cancel entries', (tester) async {
      final f = _fake('Draft');
      await _openQuote(tester, f, role: 'Reader');
      await tapKey(tester, 'quote-menu');
      expect(find.text('Ver texto do orçamento'), findsOneWidget);
      expect(find.text('Duplicar'), findsNothing);
      expect(find.text('Cancelar orçamento'), findsNothing);
      expect(find.text('Editar itens e condições'), findsNothing);
      expect(find.byKey(const ValueKey('quote-send')), findsNothing);
    });

    testWidgets('a load error is shown in place of the quote', (tester) async {
      final f = _fake('Draft')..overrides['GET /api/sales/quotes/5'] = ((_) => http.Response('', 404));
      await _openQuote(tester, f);
      expect(find.text('Registro não encontrado'), findsOneWidget);
    });
  });
}

