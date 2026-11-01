import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/reports/print_docs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

final _customer = {
  'id': 7,
  'name': 'Cliente Teste Ltda',
  'legacyCode': 'C0042',
  'company': {
    'document': '26133636000103',
    'stateRegistration': '111222333444',
    'street': 'Av. das Nações',
    'number': '100',
    'district': 'Centro',
    'city': 'São Paulo',
    'uf': 'SP',
    'zipCode': '01000000',
    'contact': 'Maria',
    'phone': '1133334444',
    'email': 'compras@cliente.test',
  },
};

final _product = {'id': 3, 'shape': 'Round', 'diameterMm': 12.7, 'thicknessMm': 1, 'lengthMm': 6000};

ApiClient _api({bool customerFails = false, bool productFails = false, Map<String, dynamic>? product, Map<String, dynamic>? customer}) {
  final client = MockClient((r) async {
    if (r.url.path.startsWith('/api/customers/')) return customerFails ? _json({'message': 'erro'}, 500) : _json(customer ?? _customer);
    if (r.url.path.startsWith('/api/products/')) return productFails ? _json({'message': 'erro'}, 500) : _json(product ?? _product);
    return _json({}, 404);
  });
  return ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok');
}

void _expectPdf(List<int> bytes) {
  expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  expect(bytes.length, greaterThan(1500));
}

Map<String, dynamic> _quote({
  Object? customerId = 7,
  List<Map<String, dynamic>>? lines,
  Map<String, dynamic>? extra,
}) => {
  'reference': 'PROP 120A',
  'customerId': customerId,
  'customerName': 'Cliente Teste Ltda',
  'addressText': 'Rua A, 10 - Embu',
  'createdAt': '2026-10-20T10:00:00Z',
  'sentAt': '2026-10-21T10:00:00Z',
  'validityDays': 15,
  'paymentTermName': '28 dias',
  'freight': 'Cif',
  'contactName': 'Maria',
  'contactEmail': 'maria@cliente.test',
  'customerReference': 'RC-9',
  'notes': 'Embalagem em pacotes.',
  'conditions': '',
  'totals': {'products': 1000, 'ipi': 50, 'total': 1050},
  'lines':
      lines ??
      [
        {'sequence': 1, 'productCode': 'T121', 'customerPartNumber': 'CL-1', 'description': 'Tubo 12 x 1', 'quantity': 100, 'unit': 'PC', 'unitPrice': 10, 'ipiPercent': 5, 'icmsPercent': 18, 'total': 1050, 'leadTimeDays': 10},
        {'sequence': 2, 'productCode': 'T122', 'description': 'Tubo 12 x 1,5', 'quantity': 12.5, 'unit': 'KG', 'unitPrice': 4.1234, 'total': 51.5, 'deliveryDate': '2026-11-30'},
        {'sequence': 3, 'productCode': 'T123', 'description': 'Tubo 16', 'quantity': 1, 'unit': 'PC', 'unitPrice': 1, 'total': 1},
      ],
  ...?extra,
};

Map<String, dynamic> _salesOrder({List<Map<String, dynamic>>? lines, Map<String, dynamic>? extra}) => {
  'reference': 'PV 55',
  'customerId': 7,
  'customerName': 'Cliente Teste Ltda',
  'addressText': 'Rua A, 10 - Embu',
  'createdAt': '2026-10-22T09:00:00Z',
  'paymentTermName': '28 dias',
  'freight': 'Cif',
  'customerPo': 'PO-777',
  'notes': 'Urgente',
  'lines':
      lines ??
      [
        {'productCode': 'T121', 'customerPartNumber': 'CL-1', 'description': 'Tubo 12 x 1', 'quantity': 100, 'unit': 'PC', 'unitPrice': 10, 'ipiPercent': 5, 'icmsPercent': 18, 'dueDate': '2026-11-20'},
        {'productCode': 'T122', 'quantity': 12.5, 'unit': 'kg', 'unitPrice': 4.5, 'dueDate': '2026-11-25'},
      ],
  ...?extra,
};

Map<String, dynamic> _productionOrder({List<Map<String, dynamic>>? ops, List<Map<String, dynamic>>? mats, Map<String, dynamic>? extra}) => {
  'reference': 'OF 900',
  'customerId': 7,
  'productId': 3,
  'productCode': 'T121',
  'productName': 'Tubo 12 x 1',
  'productUnit': 'PC',
  'quantity': 250,
  'dueDate': '2026-12-01',
  'customerPo': 'PO-777',
  'primaryTube': 'Redondo 20 x 1,5',
  'notes': 'Embalar em caixas',
  'operations':
      ops ??
      [
        {'sequence': 10, 'description': 'Perfilar', 'tolerance': '±0,1', 'measureStart': '20', 'measureEnd': '12,7', 'machineCode': 'PF-01', 'external': false},
        {'sequence': 20, 'description': 'Zincagem', 'external': true},
      ],
  'materials':
      mats ??
      [
        {'code': 'BOB-15', 'description': 'Bobina 1,5mm'},
        {'code': 'BOB-15', 'description': 'Bobina 1,5mm'},
        {'code': 'FIO-2'},
      ],
  ...?extra,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildQuotePdf', () {
    test('builds a quote with lead time, delivery date and plain lines', () async {
      final bytes = await buildQuotePdf(_api(), _quote());
      _expectPdf(bytes);
    });

    test('works when the customer lookup fails (500)', () async {
      _expectPdf(await buildQuotePdf(_api(customerFails: true), _quote()));
    });

    test('works without a customer id, custom prazo, valid-until date and free-text conditions', () async {
      final q = _quote(
        customerId: null,
        lines: [
          {'sequence': 1, 'productCode': 'T121', 'description': 'Tubo', 'quantity': 3, 'unit': 'PC', 'unitPrice': 2, 'total': 6, 'deliveryDate': '2026-12-10'},
        ],
        extra: {'paymentTermName': null, 'customPaymentTerm': '30/45/60 dias', 'validUntil': '2026-11-30', 'sentAt': null, 'notes': null, 'conditions': 'Condições específicas.', 'freight': 'CustomerPickup'},
      );
      _expectPdf(await buildQuotePdf(_api(), q));
    });

    test('works with no dates at all', () async {
      final q = _quote(extra: {'sentAt': null, 'createdAt': null, 'freight': null, 'contactName': null, 'contactEmail': null});
      _expectPdf(await buildQuotePdf(_api(), q));
    });

    test('a long item list flows onto more pages', () async {
      final many = _quote(
        lines: [
          for (var i = 1; i <= 80; i++) {'sequence': i, 'productCode': 'T$i', 'description': 'Tubo $i', 'quantity': i, 'unit': 'PC', 'unitPrice': 1.5, 'total': i * 1.5, 'leadTimeDays': 10},
        ],
      );
      final one = await buildQuotePdf(_api(), _quote());
      final bytes = await buildQuotePdf(_api(), many);
      expect(bytes.length, greaterThan(one.length));
    });
  });

  group('buildSalesOrderPdf', () {
    test('builds one page per item', () async {
      final one = await buildSalesOrderPdf(_api(), _salesOrder(lines: [_salesOrder()['lines'][0] as Map<String, dynamic>]));
      final two = await buildSalesOrderPdf(_api(), _salesOrder());
      _expectPdf(one);
      _expectPdf(two);
      expect(two.length, greaterThan(one.length));
    });

    test('uses the default address when the company has no street, and customer pickup freight', () async {
      final customer = {
        'id': 8,
        'defaultAddress': {'street': 'Rua B', 'number': '5', 'district': 'Bairro', 'city': 'Cotia', 'uf': 'SP', 'zipCode': '06700000', 'document': '11222333000181', 'buyer': 'João', 'phone': '1122223333', 'email': 'j@x.test'},
      };
      final bytes = await buildSalesOrderPdf(_api(customer: customer), _salesOrder(extra: {'freight': 'CustomerPickup', 'customerPo': null, 'notes': null, 'createdAt': null}));
      _expectPdf(bytes);
    });

    test('works when the customer lookup fails and uses the custom prazo', () async {
      final bytes = await buildSalesOrderPdf(_api(customerFails: true), _salesOrder(extra: {'paymentTermName': null, 'customPaymentTerm': '45 dias'}));
      _expectPdf(bytes);
    });
  });

  group('buildProductionOrderPdf', () {
    test('builds an OF with internal and outside operations', () async {
      _expectPdf(await buildProductionOrderPdf(_api(), _productionOrder()));
    });

    test('works when customer and product lookups fail', () async {
      _expectPdf(await buildProductionOrderPdf(_api(customerFails: true, productFails: true), _productionOrder()));
    });

    test('rectangular product, no materials, no operations and no customer PO', () async {
      final product = {'id': 3, 'shape': 'Rectangular', 'widthMm': 40, 'heightMm': 20.5, 'thicknessMm': 2, 'lengthMm': 6000};
      final of = _productionOrder(ops: [], mats: [], extra: {'customerId': null, 'customerPo': null, 'primaryTube': null, 'quantity': null});
      _expectPdf(await buildProductionOrderPdf(_api(product: product), of));
    });

    test('product without measures falls back to the product name', () async {
      _expectPdf(await buildProductionOrderPdf(_api(product: {'id': 3, 'shape': 'Round'}), _productionOrder()));
    });

    test('seven or more operations leave a single blank row', () async {
      final ops = [
        for (var i = 1; i <= 8; i++) {'sequence': i * 10, 'description': 'Operação $i', 'machineCode': 'M$i'},
      ];
      _expectPdf(await buildProductionOrderPdf(_api(), _productionOrder(ops: ops)));
    });
  });
}
