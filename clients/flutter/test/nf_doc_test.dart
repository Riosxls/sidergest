import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/reports/nf_doc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fiscal = NfFiscal(number: '2581', series: '001', accessKey: '35261011222333000181550010000025811123456785', protocol: '135261234567890');

  ApiClient api(Map<String, Object> routes, List<String> log) => ApiClient(
    baseUrl: 'http://api.test',
    token: 'tok',
    client: MockClient((r) async {
      log.add(r.url.path);
      final hit = routes[r.url.path];
      return hit == null ? json({'title': 'x', 'status': 500}, 500) : json(hit);
    }),
  );

  final delivery = {
    'orderId': 3,
    'customerId': 9,
    'customerName': 'Metalúrgica Alfa',
    'reference': 'ENT-12',
    'grossWeightKg': 42.5,
    'packages': 2,
    'addressText': 'Rua A, 10',
    'lines': [
      {'orderLineId': 31, 'productId': 5, 'productCode': 'TB-100', 'description': 'Tubo redondo 25x1,5', 'unit': 'PC', 'quantity': 10},
    ],
  };

  bool isPdf(List<int> b) => String.fromCharCodes(b.take(5)) == '%PDF-' && b.length > 2000;

  test('sale NF reads the order, customer and product NCM, then renders a PDF', () async {
    final log = <String>[];
    final bytes = await buildSaleNfPdf(
      api({
        '/api/sales/orders/3': {
          'customerPo': 'PC-77',
          'paymentTermName': '30/60/90',
          'lines': [
            {'id': 31, 'unitPrice': 125.05, 'icmsPercent': 18, 'ipiPercent': 5},
          ],
        },
        '/api/customers/9': {
          'company': {'document': '12345678000190', 'stateRegistration': '111222333', 'street': 'Rua das Flores', 'number': '100', 'city': 'São Paulo', 'uf': 'SP'},
        },
        '/api/products/5': {'ncm': '7306.61.00'},
      }, log),
      delivery,
      fiscal,
    );
    expect(isPdf(bytes), isTrue);
    expect(log, containsAll(['/api/sales/orders/3', '/api/customers/9', '/api/products/5']));
  });

  test('sale NF still renders when the order, customer and product lookups fail', () async {
    final bytes = await buildSaleNfPdf(api({}, []), delivery, const NfFiscal());
    expect(isPdf(bytes), isTrue);
  });

  test('sale NF with no payment term has no installments and a custom term still renders', () async {
    final bytes = await buildSaleNfPdf(
      api({
        '/api/sales/orders/3': {
          'customPaymentTerm': '28 dias',
          'lines': [
            {'id': 31, 'unitPrice': 10, 'icmsPercent': 0, 'ipiPercent': 0},
          ],
        },
      }, []),
      delivery,
      fiscal,
    );
    expect(isPdf(bytes), isTrue);
  });

  test('outside-processing shipment renders the 5901 remessa with the supplier address', () async {
    final log = <String>[];
    final bytes = await buildOutsideNfPdf(
      api({
        '/api/production/orders/4': {
          'reference': 'OF-4',
          'productId': 5,
          'productCode': 'TB-100',
          'productName': 'Tubo redondo',
          'productUnit': 'kg',
          'operations': [
            {'sequence': 20, 'description': 'Recozimento'},
          ],
        },
        '/api/suppliers/8/addresses': [
          {'document': '98765432000110', 'stateRegistration': '555', 'street': 'Av. Industrial', 'number': '1', 'city': 'Guarulhos', 'uf': 'SP'},
        ],
        '/api/products/5': {'ncm': '73066100'},
      }, log),
      {'orderId': 4, 'operationSequence': 20, 'supplierId': 8, 'supplierName': 'Térmica Beta', 'quantity': 500, 'serviceValue': 1500, 'notes': 'Retorno em 5 dias'},
      fiscal,
    );
    expect(isPdf(bytes), isTrue);
    expect(log, contains('/api/suppliers/8/addresses'));
  });

  test('outside-processing shipment with zero quantity does not divide by zero', () async {
    final bytes = await buildOutsideNfPdf(api({}, []), {'orderId': 4, 'operationSequence': 20, 'supplierId': 8, 'supplierName': 'Térmica Beta', 'quantity': 0, 'serviceValue': 100}, const NfFiscal());
    expect(isPdf(bytes), isTrue);
  });
}
