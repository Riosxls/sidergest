import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/reports/print_docs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'sales_more_support.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

ApiClient _api(List<String> log, {int settingsStatus = 200}) => ApiClient(
  baseUrl: 'http://api.test',
  token: 'tok',
  client: MockClient((r) async {
    log.add('${r.method} ${r.url.path}');
    if (r.url.path == '/api/fiscal/settings') {
      return settingsStatus == 200
          ? _json({
              'companyName': 'EBT Indústria Ltda',
              'tradeName': 'EBT',
              'cnpj': '12345678000199',
              'stateRegistration': '111222333',
              'street': 'Rua das Indústrias',
              'number': '10',
              'district': 'Distrito',
              'city': 'São Paulo',
              'uf': 'SP',
              'zipCode': '01000000',
              'phone': '1130000000',
            })
          : _json({'title': 'Sem acesso'}, settingsStatus);
    }
    if (r.url.path.startsWith('/api/customers/')) {
      return _json({
        'id': 2,
        'name': 'BTS Tubos',
        'company': {'document': '98765432000100'},
      });
    }
    return _json({});
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // the PDFs load their fonts from the asset bundle

  group('quotePrintWarning', () {
    test('names what makes a quote not final, and is silent for one that may go to the customer', () {
      expect(quotePrintWarning({'status': 'Draft'}), startsWith('RASCUNHO'));
      expect(quotePrintWarning({'status': 'PendingApproval'}), contains('autorização do gerente'));
      expect(quotePrintWarning({'status': 'Approved'}), startsWith('RASCUNHO'));
      expect(quotePrintWarning({'status': 'Cancelled'}), 'CANCELADO');
      expect(quotePrintWarning({'status': 'Expired'}), 'VALIDADE EXPIRADA');
      expect(quotePrintWarning({'status': 'Sent', 'supersededById': 8, 'supersededBy': 'PROP 8A'}), 'SUBSTITUÍDA pela revisão PROP 8A');
      for (final s in ['Sent', 'Accepted', 'PurchaseOrder', 'Converted', 'Rejected']) {
        expect(quotePrintWarning({'status': s}), isNull, reason: s);
      }
    });
  });

  group('quote PDF', () {
    Map<String, dynamic> quote(String status) => {...defaultQuote(), 'status': status};

    test('reads the company data from the fiscal settings and builds', () async {
      final log = <String>[];
      final bytes = await buildQuotePdf(_api(log), quote('Sent'));
      expect(bytes.length, greaterThan(1000));
      expect(log, contains('GET /api/fiscal/settings'));
    });

    test('still builds, with the company name only, when the settings are not available', () async {
      final log = <String>[];
      final bytes = await buildQuotePdf(_api(log, settingsStatus: 403), quote('Sent'));
      expect(bytes.length, greaterThan(1000));
    });

    test('a draft builds with its banner', () async {
      final sent = await buildQuotePdf(_api([]), quote('Sent'));
      final draft = await buildQuotePdf(_api([]), quote('Draft'));
      expect(draft.length, isNot(sent.length)); // the banner adds drawing commands to every page
    });
  });

  group('sales order PDF', () {
    test('builds from the line spec and the saved totals', () async {
      final order = defaultOrder();
      final bytes = await buildSalesOrderPdf(_api([]), order);
      expect(bytes.length, greaterThan(1000));
    });

    test('builds for a line without a spec', () async {
      final order = defaultOrder();
      ((order['lines'] as List).first as Map<String, dynamic>)['spec'] = null;
      final bytes = await buildSalesOrderPdf(_api([]), order);
      expect(bytes.length, greaterThan(1000));
    });
  });
}
