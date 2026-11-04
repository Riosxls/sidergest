import 'dart:convert';

import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sales_more_support.dart';

Future<MoreFake> _open(WidgetTester tester, {String status = 'Draft', bool mail = true, bool needsApproval = false}) async {
  final f = MoreFake();
  f.quote
    ..['status'] = status
    ..['needsApproval'] = needsApproval
    ..['contactEmail'] = 'compras@bts.com';
  if (status == 'Sent') {
    f.quote
      ..['validUntil'] = '2099-01-01'
      ..['sentAt'] = '2026-10-26T12:00:00Z'
      ..['sentTo'] = 'compras@bts.com';
  }
  f.overrides['GET /api/system/mail'] = (_) => jsonResp({'enabled': mail, 'from': mail ? 'orcamentos@ebt.com.br' : null});
  f.overrides['POST /api/sales/quotes/5/email'] = (r) {
    f.quote
      ..['status'] = 'Sent'
      ..['sentTo'] = f.body(r)['to']
      ..['validUntil'] = '2099-01-01';
    return jsonResp(f.quote);
  };
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpMore(tester, f, (s) => QuoteScreen(session: s, id: 5));
  return f;
}

void main() {
  testWidgets('without SMTP on the server only "Registrar envio" is offered', (tester) async {
    await _open(tester, mail: false);
    expect(find.byKey(const ValueKey('quote-email')), findsNothing);
    expect(find.byKey(const ValueKey('quote-send')), findsOneWidget);
  });

  testWidgets('a quote waiting for the discount approval is not mailed', (tester) async {
    await _open(tester, needsApproval: true);
    expect(find.byKey(const ValueKey('quote-email')), findsNothing);
    expect(find.text('Enviar para autorização'), findsOneWidget);
  });

  testWidgets('"Enviar ao cliente" asks for valid addresses, then posts the PDF and registers the send', (tester) async {
    final f = await _open(tester);
    expect(find.byKey(const ValueKey('quote-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('quote-send')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quote-email')));
    await tester.pumpAndSettle();
    expect(find.text('Enviar orçamento por e-mail'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('email-to'))).controller!.text, 'compras@bts.com');
    expect(find.textContaining('orcamentos@ebt.com.br'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('email-to')), 'sem-arroba');
    await tester.tap(find.byKey(const ValueKey('email-send')));
    await tester.pumpAndSettle();
    expect(find.text('E-mail inválido: sem-arroba'), findsOneWidget);
    expect(f.called('POST', '/api/sales/quotes/5/email'), isFalse);

    await tester.enterText(find.byKey(const ValueKey('email-to')), 'a@bts.com; b@bts.com');
    await tester.enterText(find.byKey(const ValueKey('email-cc')), 'vendas@ebt.com.br');
    await tester.tap(find.byKey(const ValueKey('email-send')));
    await tester.pumpAndSettle();

    final body = f.body(f.last('POST', '/api/sales/quotes/5/email'));
    expect(body['to'], 'a@bts.com; b@bts.com');
    expect(body['cc'], 'vendas@ebt.com.br');
    expect(body['subject'], 'PROP 31 · EBT');
    expect(body['fileName'], 'Orçamento PROP 31.pdf');
    expect(utf8.decode(base64Decode(body['pdfBase64'] as String).sublist(0, 5)), '%PDF-');
    expect(find.text('E-mail enviado e envio registrado'), findsOneWidget);
    expect(find.text('Aguardando resposta do cliente'), findsOneWidget);
  });

  testWidgets('a quote already sent can be mailed again', (tester) async {
    await _open(tester, status: 'Sent');
    await tester.tap(find.byKey(const ValueKey('quote-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quote-menu-email')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quote-menu-email')));
    await tester.pumpAndSettle();
    expect(find.textContaining('este é um reenvio'), findsOneWidget);
  });

  testWidgets('a refused send shows the mail server message, not a generic server error', (tester) async {
    final f = await _open(tester);
    f.overrides['POST /api/sales/quotes/5/email'] = (_) => jsonResp({'message': 'O servidor de e-mail recusou o usuário ou a senha.'}, 502);
    await tester.tap(find.byKey(const ValueKey('quote-email')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('email-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('recusou o usuário ou a senha'), findsOneWidget);
    expect(find.textContaining('avise o suporte'), findsNothing);
  });
}
