import 'package:ebt_engenharia/screens/sales_orders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'sales_more_support.dart';

Map<String, dynamic> _line0(MoreFake f) => (f.order['lines'] as List).first as Map<String, dynamic>;

Future<void> _skipGate(WidgetTester tester) async {
  if (find.byKey(const ValueKey('gate-skip')).evaluate().isEmpty) return;
  await tapKey(tester, 'gate-skip');
}

MoreFake _released({bool ready = false, bool certified = false, String status = 'Released'}) {
  final f = MoreFake();
  f.order['status'] = status;
  f.order['ready'] = ready;
  f.order['releasedBy'] = 'joao';
  f.order['releasedAt'] = '2026-10-27T12:00:00Z';
  _line0(f)
    ..['ready'] = ready
    ..['fromStock'] = 30;
  if (certified) {
    f.certs = [
      {'id': 70, 'reference': 'CERT 1', 'status': 'Issued', 'description': 'Tubo', 'quantity': 100, 'unit': 'PC', 'issueDate': '2026-10-28'},
    ];
  }
  return f;
}

void main() {
  group('order list', () {
    testWidgets('shows alerts, filters by late orders, clears filters and creates', (tester) async {
      final fake = MoreFake();
      fake.order
        ..['status'] = 'Released'
        ..['late'] = true
        ..['ready'] = true;
      await pumpMore(tester, fake, (s) => SalesOrdersScreen(session: s));
      expect(fake.log.first.url.queryParameters['open'], 'true');
      expect(find.text('Atrasado · Pronto p/ expedir'), findsOneWidget);
      expect(find.text('PV 9'), findsOneWidget);
      await tapKey(tester, 'orders-late');
      expect(fake.log.last.url.queryParameters['late'], 'true');
      await tapText(tester, 'Somente abertos');
      expect(fake.log.last.url.queryParameters.containsKey('open'), isFalse);
      await tapText(tester, 'Novo pedido');
      expect(find.text('Novo pedido de venda'), findsOneWidget);
      expect(find.text('Pedido de compra do cliente'), findsOneWidget);
    });

    testWidgets('a reader gets no new order button and a tap opens the order', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrdersScreen(session: s), role: 'Reader');
      expect(find.text('Novo pedido'), findsNothing);
      await tapText(tester, 'PV 9');
      expect(find.text('PV 9 · BTS Tubos'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-menu')), findsNothing);
    });
  });

  group('order screen', () {
    testWidgets('a load error is shown in place of the order', (tester) async {
      final fake = MoreFake()..overrides['GET /api/sales/orders/9'] = (_) => http.Response('', 404);
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Registro não encontrado'), findsOneWidget);
    });

    testWidgets('a failing quote or certificate lookup does not hide the order', (tester) async {
      final fake = MoreFake()
        ..overrides['GET /api/sales/quotes/5'] = ((_) => http.Response('', 500))
        ..overrides['GET /api/sales/certificates'] = ((_) => http.Response('', 500));
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('PV 9 · BTS Tubos'), findsOneWidget);
      expect(find.textContaining('Pedido digitado sem orçamento'), findsOneWidget);
    });

    testWidgets('shows measures, standard and material need of the item', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.textContaining('Ø25,4 × e1,5 × c'), findsOneWidget);
      expect(find.textContaining('NBR 5599'), findsOneWidget);
      expect(find.text('Itens (1)'), findsOneWidget);
      expect(find.text('50.000,00 em aberto de 10.500,00'), findsNothing);
      expect(find.textContaining('em aberto de'), findsOneWidget);
    });

    testWidgets('Editar opens the editor for the order and saving shows the result', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await openMenu(tester, 'order-menu', 'Editar');
      expect(find.text('Editar PV 9'), findsOneWidget);
      await tapKey(tester, 'quote-save');
      expect(fake.last('PUT', '/api/sales/orders/9').url.path, '/api/sales/orders/9');
      expect(find.text('PV 9 · BTS Tubos'), findsOneWidget);
    });

    testWidgets('cancelling an order with nothing attached needs a reason and posts it', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await openMenu(tester, 'order-menu', 'Cancelar pedido');
      expect(find.text('Cancelar PV 9?'), findsOneWidget);
      expect(find.textContaining('O pedido não tem OFs, entregas nem reservas.'), findsOneWidget);
      expect(find.byKey(const ValueKey('reason-option')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('confirm-step'))).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Cliente desistiu');
      await tester.pump();
      await tapKey(tester, 'confirm-step');
      expect(fake.body(fake.last('POST', '/api/sales/orders/9/cancel')), {'reason': 'Cliente desistiu', 'cancelProduction': false});
      expect(find.text('Pedido cancelado'), findsWidgets);
      expect(find.byKey(const ValueKey('order-menu')), findsNothing);
      expect(find.byKey(const ValueKey('print-panel')), findsNothing);
    });

    testWidgets('backing out of the cancel dialog sends nothing', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await openMenu(tester, 'order-menu', 'Cancelar pedido');
      await tapText(tester, 'Voltar');
      expect(fake.called('POST', '/api/sales/orders/9/cancel'), isFalse);
    });

    testWidgets('cancel is blocked by shipped deliveries and a failing preview is reported', (tester) async {
      final fake = MoreFake()
        ..overrides['GET /api/sales/orders/9/cancel-preview'] = ((_) => jsonResp({'plannedDeliveries': <String>[], 'shippedDeliveries': ['ENT 3'], 'productionOrders': <Object>[], 'reservations': 0}));
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await openMenu(tester, 'order-menu', 'Cancelar pedido');
      expect(find.textContaining('Há entregas já expedidas (ENT 3)'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      fake.overrides['GET /api/sales/orders/9/cancel-preview'] = (_) => jsonResp({'title': 'Falha', 'detail': 'sem preview'}, 500);
      await tester.pump(const Duration(seconds: 5));
      await openMenu(tester, 'order-menu', 'Cancelar pedido');
      expect(find.text('Falha: sem preview'), findsOneWidget);
    });

    testWidgets('a failed cancel keeps the order and shows the API message', (tester) async {
      final fake = MoreFake()..overrides['POST /api/sales/orders/9/cancel'] = ((_) => jsonResp({'title': 'Bloqueado', 'detail': 'Há NF emitida'}, 409));
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await openMenu(tester, 'order-menu', 'Cancelar pedido');
      await tester.enterText(find.byKey(const ValueKey('reason-field')), 'x');
      await tester.pump();
      await tapKey(tester, 'confirm-step');
      expect(find.text('Bloqueado: Há NF emitida'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-menu')), findsOneWidget);
    });

    testWidgets('releasing with the credit limit exceeded lets a manager authorize it', (tester) async {
      final fake = MoreFake();
      fake.order['credit'] = {'limit': 5000, 'open': 10500, 'thisOrder': 0, 'exceeded': true};
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9), role: 'SalesManager');
      await tapKey(tester, 'order-release');
      await _skipGate(tester);
      expect(find.byKey(const ValueKey('override-credit')), findsOneWidget);
      await tapKey(tester, 'use-stock');
      await tapKey(tester, 'override-credit');
      await tapKey(tester, 'confirm-step');
      expect(fake.body(fake.last('POST', '/api/sales/orders/9/release')), {'useStock': false, 'overrideCredit': true});
      expect(find.text('Pedido liberado para produção'), findsOneWidget);
      expect(find.textContaining('Em produção'), findsWidgets);
    });

    testWidgets('a salesperson without approval rights sees no credit override and a failed release is reported', (tester) async {
      final fake = MoreFake()..overrides['POST /api/sales/orders/9/release'] = ((_) => jsonResp({'title': 'Crédito', 'detail': 'Limite excedido'}, 409));
      fake.order['credit'] = {'limit': 5000, 'open': 10500, 'thisOrder': 0, 'exceeded': true};
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapKey(tester, 'order-release');
      await _skipGate(tester);
      expect(find.byKey(const ValueKey('override-credit')), findsNothing);
      await tapKey(tester, 'confirm-step');
      expect(fake.body(fake.last('POST', '/api/sales/orders/9/release')), {'useStock': true});
      expect(find.text('Crédito: Limite excedido'), findsOneWidget);
      expect(find.text('Liberar para produção'), findsWidgets); // still created
    });

    testWidgets('a role that cannot release has no release button', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9), role: 'Reader');
      expect(find.byKey(const ValueKey('order-release')), findsNothing);
      expect(find.byKey(const ValueKey('order-print-card')), findsOneWidget);
    });
  });

  group('certificate step', () {
    testWidgets('ready without certificate: manager waives it and then asks for it again', (tester) async {
      final fake = _released(ready: true);
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9), role: 'SalesManager');
      expect(find.text('Produção pronta · falta o certificado'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-certificate')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-new-certificate')), findsOneWidget);
      await tapKey(tester, 'order-certificate-waive');
      expect(fake.body(fake.last('POST', '/api/sales/orders/9/certificate-waiver')), {'waived': true});
      expect(find.text('Certificado dispensado'), findsOneWidget);
      expect(find.text('Pronto para expedir'), findsOneWidget);
      expect(find.text('Dispensado para este pedido'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Dispensado · exigir novamente'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Dispensado · exigir novamente'));
      await tester.pumpAndSettle();
      expect(fake.body(fake.last('POST', '/api/sales/orders/9/certificate-waiver')), {'waived': false});
      expect(find.text('Produção pronta · falta o certificado'), findsOneWidget);
    });

    testWidgets('a salesperson cannot waive the certificate and the re-require button is disabled', (tester) async {
      final fake = _released(ready: true);
      fake.order['certificateWaived'] = true;
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.byKey(const ValueKey('order-certificate-waive')), findsNothing);
      final btn = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Dispensado · exigir novamente'));
      expect(btn.onPressed, isNull);
      expect(find.text('Pronto para expedir'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-new-certificate')), findsNothing);
    });

    testWidgets('an issued certificate unlocks shipping and is listed with its print shortcut', (tester) async {
      final fake = _released(ready: true, certified: true);
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Pronto para expedir'), findsOneWidget);
      expect(find.text('Certificados de qualidade (1)'), findsOneWidget);
      expect(find.text('CERT 1'), findsWidgets);
      expect(find.byKey(const ValueKey('doc-print-certificate-70')), findsOneWidget);
      expect(find.text('Pronto'), findsOneWidget);
    });
  });

  group('deliveries', () {
    testWidgets('dialog validates the date and quantities, then posts and opens the delivery', (tester) async {
      final fake = _released(certified: true);
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapKey(tester, 'order-deliver');
      expect(find.text('Programar entrega · PV 9'), findsOneWidget);
      expect(find.textContaining('Saldo 100 PC · disponível 30'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('dl-qty-40'))).controller!.text, '30');
      await tester.enterText(find.widgetWithText(TextField, 'Data *'), '99/99/9999');
      await tapKey(tester, 'delivery-ok');
      expect(find.text('Data inválida'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Data *'), '28/10/2026');
      await tester.enterText(find.byKey(const ValueKey('dl-qty-40')), '0');
      await tapKey(tester, 'delivery-ok');
      expect(find.text('Informe a quantidade de ao menos um item'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('dl-qty-40')), '25');
      await tester.enterText(find.widgetWithText(TextField, 'Observações'), ' Entregar de manhã ');
      await tapKey(tester, 'delivery-ok');
      final b = fake.body(fake.last('POST', '/api/sales/orders/9/deliveries'));
      expect(b['plannedDate'], '2026-10-28');
      expect(b['notes'], 'Entregar de manhã');
      expect(b['lines'], [
        {'orderLineId': 40, 'quantity': 25},
      ]);
      expect(find.text('Entrega programada'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('going back from the dialog posts nothing', (tester) async {
      final fake = _released(certified: true);
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapKey(tester, 'order-deliver');
      await tapText(tester, 'Voltar');
      expect(fake.called('POST', '/api/sales/orders/9/deliveries'), isFalse);
    });

    testWidgets('a planned delivery can be opened from the table', (tester) async {
      final fake = _released(certified: true);
      fake.order['deliveries'] = [
        {'id': 15, 'reference': 'ENT 15', 'plannedDate': '2026-10-28', 'status': 'Shipped', 'invoiceNumber': '1234', 'packages': 1},
      ];
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Entregas (1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-print-nf-15')), findsOneWidget);
      expect(find.textContaining('NF 1234 · ENT 15'), findsOneWidget);
      await tester.tap(find.byTooltip('Abrir').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('ENT 15'), findsWidgets);
      expect(fake.called('GET', '/api/sales/deliveries/15'), isTrue);
    });

    testWidgets('a fully planned order refuses to open the delivery dialog', (tester) async {
      final fake = _released(certified: true);
      _line0(fake)['planned'] = 100;
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapKey(tester, 'order-deliver');
      expect(find.text('Todos os itens já estão programados ou expedidos'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('order states', () {
    testWidgets('in production: late order warns, production section shows the OF and stock', (tester) async {
      final fake = _released();
      fake.order['late'] = true;
      _line0(fake)
        ..['productionOrderId'] = 12
        ..['productionReference'] = 'OF 500'
        ..['productionStatus'] = 'Released'
        ..['produced'] = 20;
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.textContaining('Em produção'), findsWidgets);
      expect(find.text('Há itens com data de entrega vencida.'), findsOneWidget);
      expect(find.text('30 do estoque + 70 na OF 500'), findsOneWidget);
      expect(find.text('50/100 · exp. 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('print-of')), findsOneWidget); // single OF: the app bar prints it
      expect(find.byKey(const ValueKey('order-print-of-12')), findsOneWidget);
    });

    testWidgets('two OFs get a print button each and the cards name them', (tester) async {
      final fake = _released();
      final lines = fake.order['lines'] as List;
      lines.add({..._line0(fake), 'id': 41, 'sequence': 20, 'productionOrderId': 13, 'productionReference': 'OF 501', 'productionStatus': 'InProduction'});
      _line0(fake)
        ..['productionOrderId'] = 12
        ..['productionReference'] = 'OF 500'
        ..['productionStatus'] = 'Released';
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.byKey(const ValueKey('print-of-12')), findsWidgets);
      expect(find.byKey(const ValueKey('print-of-13')), findsWidgets);
      expect(find.text('Imprimir OF 501'), findsOneWidget);
    });

    testWidgets('a shipped order only informs', (tester) async {
      final shipped = _released(status: 'Shipped');
      await pumpMore(tester, shipped, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Tudo expedido'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-menu')), findsNothing);
    });

    testWidgets('a delivered order only informs', (tester) async {
      final delivered = _released(status: 'Delivered');
      await pumpMore(tester, delivered, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Pedido entregue'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-menu')), findsNothing);
    });

    testWidgets('a cancelled order shows the reason and no print panel', (tester) async {
      final fake = MoreFake();
      fake.order
        ..['status'] = 'Cancelled'
        ..['statusReason'] = 'Cliente desistiu da compra';
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('Cliente desistiu da compra'), findsOneWidget);
      expect(find.byKey(const ValueKey('print-panel')), findsNothing);
    });

    testWidgets('partially shipped: balance can be closed from the menu and reschedule is offered', (tester) async {
      final fake = _released(status: 'PartiallyShipped');
      _line0(fake)['shipped'] = 40;
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapKey(tester, 'order-menu');
      await tester.tap(find.text('Encerrar saldo').last);
      await tester.pumpAndSettle();
      expect(find.text('Encerrar saldo de PV 9?'), findsOneWidget);
      expect(find.textContaining('Item 10 · TB-25: 100 → 40 PC'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Cliente cancelou o restante');
      await tester.pump();
      await tapKey(tester, 'confirm-step');
      expect(fake.body(fake.last('POST', '/api/sales/orders/9/close-balance')), {'reason': 'Cliente cancelou o restante'});
      expect(find.text('Saldo encerrado'), findsOneWidget);
      expect(find.text('Tudo expedido'), findsOneWidget);
    });

    testWidgets('reschedule saves the new dates and confirms', (tester) async {
      final fake = _released();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await openMenu(tester, 'order-menu', 'Alterar prazos ou pedido do cliente');
      await tester.enterText(find.byKey(const ValueKey('field-line-40')), '20/11/2026');
      await tester.enterText(find.byKey(const ValueKey('field-reason')), 'Cliente adiou');
      await tapText(tester, 'Salvar');
      final b = fake.body(fake.last('POST', '/api/sales/orders/9/reschedule'));
      expect(b['reason'], 'Cliente adiou');
      expect(b['lines'], [
        {'lineId': 40, 'dueDate': '2026-11-20'},
      ]);
      expect(find.text('Prazos atualizados'), findsOneWidget);
    });

    testWidgets('Ver orçamento opens the quote', (tester) async {
      final fake = MoreFake();
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tapText(tester, 'Ver orçamento');
      expect(find.textContaining('PROP 31 · BTS Tubos'), findsOneWidget);
    });
  });

  group('customer purchase order paper', () {
    testWidgets('a file type that cannot print from here says so', (tester) async {
      final fake = MoreFake();
      fake.quote
        ..['requestFileName'] = 'pedido.docx'
        ..['requestFileSize'] = 100;
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      expect(find.text('pedido.docx'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('doc-print-customer-po')));
      await tapKey(tester, 'doc-print-customer-po');
      expect(find.textContaining('Este tipo de arquivo não imprime daqui'), findsOneWidget);
    });

    testWidgets('a failed download is reported as a print failure', (tester) async {
      final fake = MoreFake();
      fake.quote
        ..['requestFileName'] = 'pedido.pdf'
        ..['requestFileSize'] = 100;
      fake.overrides['GET /api/sales/quotes/5/request-file'] = (_) => jsonResp({'title': 'Arquivo', 'detail': 'sumiu'}, 500);
      await pumpMore(tester, fake, (s) => SalesOrderScreen(session: s, id: 9));
      await tester.ensureVisible(find.byKey(const ValueKey('doc-print-customer-po')));
      await tapKey(tester, 'doc-print-customer-po');
      expect(find.text('Falha ao imprimir: Arquivo: sumiu'), findsOneWidget);
    });
  });
}
