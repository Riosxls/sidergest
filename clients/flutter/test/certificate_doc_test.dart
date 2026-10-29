import 'package:ebt_engenharia/reports/certificate_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> certificate(String company, String status) => {
    'reference': '2146-26',
    'company': company,
    'status': status,
    'issueDate': '2026-10-26',
    'customerName': 'Metalurgica Formigari Ltda.',
    'customerPo': '500956/26',
    'effectiveInvoiceNumber': '2579',
    'rawMaterialLot': '700261',
    'quantity': 1719,
    'unit': 'KG',
    'productCode': 'T121000000',
    'description': 'Tubo 12,00 X 1,00 X Rolo',
    'customerPartNumber': '20MF02-0091',
    'customerPartDescription': 'TUBO SAE 1010',
    'hardness': '66 HRB',
    'finish': 'Isento de porosidade / Manchas / Riscos e Corrosão',
    'notes': 'Certificado da origem do material de nº 1127693.',
    'approvedBy': 'Qualidade',
    'measures': [
      {'kind': 'Chemical', 'name': 'C', 'specified': '0,08 à 0,13', 'found': '0,081'},
      {'kind': 'Chemical', 'name': 'Mn', 'specified': null, 'found': null},
      {'kind': 'Dimensional', 'name': 'Diâmetro', 'specified': '12,00± 0,12', 'found': '11,99 à 12,02'},
      {'kind': 'Mechanical', 'name': 'LR', 'specified': '300 Mpa Min', 'found': '440 Mpa'},
    ],
  };

  test('builds a one-page PDF for each company and status', () async {
    for (final (company, status) in [('EBT', 'Issued'), ('BST', 'Draft'), ('EBT', 'Cancelled')]) {
      final bytes = await buildCertificatePdf(certificate(company, status));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    }
  });
}
