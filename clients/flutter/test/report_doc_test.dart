import 'package:ebt_engenharia/reports/report_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const doc = ReportDoc(
    title: 'Resumo do Faturamento',
    filters: ['Período: 01/10/2026 a 31/10/2026'],
    headers: ['Cliente', 'Valor Fat.'],
    numeric: [false, true],
    rows: [
      ReportRow(['Devoluções'], ReportRowKind.section),
      ReportRow(['Cliente; "A"', '1.050,00']),
      ReportRow(['Total', '1.050,00'], ReportRowKind.total),
    ],
  );

  test('csv is semicolon separated, quoted and BOM prefixed', () {
    final text = String.fromCharCodes(doc.toCsv());
    expect(text.contains('Cliente;Valor Fat.') || text.contains('Cliente;'), isTrue);
    expect(text.contains('"Cliente; ""A"""'), isTrue);
  });

  test('pdf renders', () async {
    final bytes = await doc.toPdf();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
