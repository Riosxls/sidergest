import 'package:ebt_engenharia/reports/danfe_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = '35261011222333000181550010000025811123456785';
  final issuer = {
    'companyName': 'EBT Tubos Ltda',
    'cnpj': '11222333000181',
    'stateRegistration': '111222333444',
    'street': 'Rua das Industrias',
    'number': '10',
    'district': 'Distrito',
    'city': 'Embu das Artes',
    'uf': 'SP',
    'zipCode': '06800000',
    'phone': '1144444444',
  };

  Map<String, dynamic> nf({String status = 'Authorized', bool simulated = false, String env = 'Production', int lines = 1}) => {
    'number': 2581,
    'series': 1,
    'status': status,
    'kind': 'Sale',
    'cfopCode': '5101',
    'accessKey': key,
    'protocol': '135261234567890',
    'environment': env,
    'simulated': simulated,
    'issuedAt': '2026-10-28T12:00:00Z',
    'recipientName': 'Cliente Teste',
    'recipientDocument': '26133636000103',
    'recipientUf': 'SP',
    'productsTotal': 1100,
    'freightTotal': 50,
    'icmsBase': 1150,
    'icmsTotal': 207,
    'ipiTotal': 57.5,
    'pisTotal': 7.15,
    'cofinsTotal': 33,
    'invoiceTotal': 1207.5,
    'additionalInfo': 'PV-1 | OF-2',
    'lines': [
      for (var i = 1; i <= lines; i++)
        {'sequence': i * 10, 'code': 'T121', 'description': 'Tubo 12 x 1', 'ncm': '73063010', 'unit': 'PC', 'quantity': 10, 'unitPrice': 110, 'total': 1100, 'icmsCst': '00', 'icmsBase': 1150, 'icmsPercent': 18, 'icmsValue': 207, 'ipiPercent': 5, 'ipiValue': 57.5},
    ],
    'installments': [
      {'sequence': 1, 'dueDate': '2026-11-25', 'amount': 1207.5},
    ],
  };

  test('formats the access key in groups of four', () {
    expect(formatAccessKey(key), '3526 1011 2223 3300 0181 5500 1000 0025 8111 2345 6785');
  });

  test('builds a PDF for authorized, simulated, homologation and cancelled NFs', () async {
    for (final d in [nf(), nf(simulated: true), nf(env: 'Homologation'), nf(status: 'Cancelled')]) {
      final bytes = await buildDanfePdf(d, issuer);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    }
  });

  test('a long item list flows onto more pages', () async {
    final one = await buildDanfePdf(nf(), issuer);
    final many = await buildDanfePdf(nf(lines: 120), issuer);
    expect(many.length, greaterThan(one.length));
    expect(String.fromCharCodes(many).contains('/Count 1'), isFalse);
  });
}
