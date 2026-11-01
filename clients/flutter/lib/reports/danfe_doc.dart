import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api.dart';
import '../entities.dart';
import '../screens/customers.dart' show fmtDocument;

/// DANFE (Documento Auxiliar da NF-e) of an NF already recorded by the API (`GET /api/fiscal/documents/{id}`), with the issuer data from
/// `GET /api/fiscal/settings`. Everything printed comes from the stored document: access key, protocol, items, totals and duplicatas.
/// Simulated (stub) and homologation NFs carry a "SEM VALOR FISCAL" banner; cancelled ones a "CANCELADA" one.

String _s(Object? v) => v == null ? '' : '$v';
num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
String _money(Object? v) => fmtNum(v, 2);

/// 44 digits in groups of four, as printed on the DANFE.
String formatAccessKey(String key) {
  final digits = key.replaceAll(RegExp(r'\D'), '');
  return [for (var i = 0; i < digits.length; i += 4) digits.substring(i, i + 4 > digits.length ? digits.length : i + 4)].join(' ');
}

String _cep(String z) {
  final d = z.replaceAll(RegExp(r'\D'), '');
  return d.length == 8 ? '${d.substring(0, 5)}-${d.substring(5)}' : z;
}

const _line = PdfColors.black;

pw.TextStyle _lbl() => const pw.TextStyle(fontSize: 5.5, fontStyle: pw.FontStyle.italic, color: PdfColors.grey800);
pw.TextStyle _val([double size = 8, bool bold = false]) => pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null);

pw.Widget _cell(String label, String value, {int flex = 1, bool right = false, bool bold = false, double size = 8, PdfColor? fill}) => pw.Expanded(
  flex: flex,
  child: pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(3, 1, 3, 2),
    decoration: pw.BoxDecoration(color: fill, border: pw.Border.all(color: _line, width: 0.4)),
    child: pw.Column(
      crossAxisAlignment: right ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(label, style: _lbl()),
        pw.Text(value, style: _val(size, bold), maxLines: 2),
      ],
    ),
  ),
);

pw.Widget _row(List<pw.Widget> cells, {double height = 24}) => pw.SizedBox(height: height, child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: cells));

pw.Widget _title(String t) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 4, bottom: 1),
  child: pw.Text(t, style: const pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
);

Future<Uint8List> buildDanfePdf(Map<String, dynamic> d, Map<String, dynamic> issuer) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
  final doc = pw.Document(title: 'DANFE NF ${d['number']}', theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: regular));

  final key = _s(d['accessKey']).replaceAll(' ', '');
  final status = _s(d['status']);
  final homolog = d['environment'] == 'Homologation';
  final simulated = d['simulated'] == true;
  final cancelled = status == 'Cancelled';
  final banner = cancelled
      ? 'NF-e CANCELADA'
      : simulated
      ? 'SEM VALOR FISCAL - AUTORIZAÇÃO SIMULADA'
      : homolog
      ? 'SEM VALOR FISCAL - AMBIENTE DE HOMOLOGAÇÃO'
      : null;
  final lines = (d['lines'] as List? ?? const []).cast<Map<String, dynamic>>();
  final installments = (d['installments'] as List? ?? const []).cast<Map<String, dynamic>>();
  final issued = DateTime.tryParse(_s(d['issuedAt']))?.toLocal();
  final issuedText = issued == null ? '' : fmtDate(issued.toIso8601String());
  final number = _s(d['number']).padLeft(9, '0');
  final numberText = '${number.substring(0, 3)}.${number.substring(3, 6)}.${number.substring(6)}';
  final issuerAddress = [
    _s(issuer['street']),
    _s(issuer['number']),
    if (_s(issuer['complement']).isNotEmpty) _s(issuer['complement']),
  ].where((e) => e.isNotEmpty).join(', ');
  final issuerCity = '${_s(issuer['district'])} - ${_cep(_s(issuer['zipCode']))} - ${_s(issuer['city'])}/${_s(issuer['uf'])}';

  final header = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (banner != null)
        pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          margin: const pw.EdgeInsets.only(bottom: 3),
          color: cancelled ? PdfColors.red100 : PdfColors.amber100,
          child: pw.Text(banner, style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ),
      pw.SizedBox(
        height: 92,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.4)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('IDENTIFICAÇÃO DO EMITENTE', style: _lbl()),
                    pw.SizedBox(height: 2),
                    pw.Text(_s(issuer['companyName']).toUpperCase(), style: _val(10, true)),
                    pw.Text(issuerAddress, style: _val(7)),
                    pw.Text(issuerCity, style: _val(7)),
                    if (_s(issuer['phone']).isNotEmpty) pw.Text('Fone: ${_s(issuer['phone'])}', style: _val(7)),
                  ],
                ),
              ),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.4)),
                child: pw.Column(
                  children: [
                    pw.Text('DANFE', style: _val(14, true)),
                    pw.Text('Documento Auxiliar da\nNota Fiscal Eletrônica', style: _val(6), textAlign: pw.TextAlign.center),
                    pw.SizedBox(height: 3),
                    pw.Text('0 - ENTRADA\n1 - SAÍDA', style: _val(6)),
                    pw.SizedBox(height: 2),
                    pw.Text('Nº $numberText', style: _val(9, true)),
                    pw.Text('SÉRIE ${_s(d['series']).padLeft(3, '0')}', style: _val(8, true)),
                  ],
                ),
              ),
            ),
            pw.Expanded(
              flex: 6,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.4)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      height: 34,
                      width: double.infinity,
                      child: key.length == 44 ? pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: key, drawText: false) : pw.SizedBox(),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text('CHAVE DE ACESSO', style: _lbl()),
                    pw.Text(formatAccessKey(key), style: _val(8, true)),
                    pw.SizedBox(height: 2),
                    pw.Text('Consulta de autenticidade no portal nacional da NF-e (www.nfe.fazenda.gov.br/portal) ou no site da SEFAZ autorizadora.', style: _val(5.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      _row([
        _cell('NATUREZA DA OPERAÇÃO', '${_s(d['cfopCode'])} - ${_s(d['natureOfOperation']).isEmpty ? (d['kind'] == 'OutsideShipment' ? 'REMESSA PARA INDUSTRIALIZAÇÃO' : 'VENDA DE MERCADORIA') : _s(d['natureOfOperation'])}', flex: 5),
        _cell(
          'PROTOCOLO DE AUTORIZAÇÃO DE USO',
          _s(d['protocol']).isEmpty ? 'Aguardando autorização' : '${_s(d['protocol'])}${issuedText.isEmpty ? '' : ' - $issuedText'}',
          flex: 5,
        ),
      ]),
      _row([_cell('INSCRIÇÃO ESTADUAL', _s(issuer['stateRegistration'])), _cell('CNPJ', fmtDocument(issuer['cnpj']))]),
      _title('DESTINATÁRIO / REMETENTE'),
      _row([
        _cell('NOME / RAZÃO SOCIAL', _s(d['recipientName']), flex: 6),
        _cell('CNPJ / CPF', fmtDocument(d['recipientDocument']), flex: 3),
        _cell('DATA DA EMISSÃO', issuedText, flex: 2),
      ]),
      _row([_cell('UF', _s(d['recipientUf']))]),
      _title('CÁLCULO DO IMPOSTO'),
      _row([
        _cell('BASE DE CÁLC. DO ICMS', _money(d['icmsBase']), right: true),
        _cell('VALOR DO ICMS', _money(d['icmsTotal']), right: true),
        _cell('VALOR DO PIS', _money(d['pisTotal']), right: true),
        _cell('VALOR DA COFINS', _money(d['cofinsTotal']), right: true),
        _cell('VALOR TOTAL DOS PRODUTOS', _money(d['productsTotal']), right: true),
      ]),
      _row([
        _cell('VALOR DO FRETE', _money(d['freightTotal']), right: true),
        _cell('VALOR DO IPI', _money(d['ipiTotal']), right: true),
        _cell('VALOR TOTAL DA NOTA', _money(d['invoiceTotal']), right: true, bold: true, size: 10, flex: 2),
      ]),
      if (installments.isNotEmpty) ...[
        _title('FATURA / DUPLICATAS'),
        pw.Wrap(
          children: [
            for (final i in installments)
              pw.Container(
                width: 120,
                padding: const pw.EdgeInsets.fromLTRB(3, 1, 3, 2),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.4)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Parcela ${_s(i['sequence']).padLeft(3, '0')}', style: _lbl()),
                    pw.Text('${fmtDate(i['dueDate'])}   R\$ ${_money(i['amount'])}', style: _val(7.5)),
                  ],
                ),
              ),
          ],
        ),
      ],
      _title('DADOS DOS PRODUTOS / SERVIÇOS'),
    ],
  );

  pw.TableRow head() => pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
    children: [
      for (final h in ['CÓDIGO', 'DESCRIÇÃO', 'NCM', 'CST', 'CFOP', 'UN', 'QTD.', 'V. UNIT.', 'V. TOTAL', 'BC ICMS', 'V. ICMS', 'V. IPI', 'ALÍQ. ICMS/IPI'])
        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(h, style: const pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold))),
    ],
  );
  pw.Widget c(String t, {bool right = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(2),
    child: pw.Text(t, style: _val(6.5), textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
  );
  final table = pw.Table(
    border: pw.TableBorder.all(color: _line, width: 0.3),
    columnWidths: {
      0: const pw.FlexColumnWidth(2.2),
      1: const pw.FlexColumnWidth(5),
      2: const pw.FlexColumnWidth(2),
      3: const pw.FlexColumnWidth(1),
      4: const pw.FlexColumnWidth(1.2),
      5: const pw.FlexColumnWidth(0.9),
      6: const pw.FlexColumnWidth(1.6),
      7: const pw.FlexColumnWidth(1.8),
      8: const pw.FlexColumnWidth(1.9),
      9: const pw.FlexColumnWidth(1.8),
      10: const pw.FlexColumnWidth(1.6),
      11: const pw.FlexColumnWidth(1.5),
      12: const pw.FlexColumnWidth(1.6),
    },
    children: [
      head(),
      for (final l in lines)
        pw.TableRow(
          children: [
            c(_s(l['code'])),
            c(_s(l['description'])),
            c(_s(l['ncm'])),
            c(_s(l['icmsCst'])),
            c(_s(d['cfopCode'])),
            c(_s(l['unit'])),
            c(fmtNum(l['quantity'], 4), right: true),
            c(fmtNum(l['unitPrice'], 4), right: true),
            c(_money(l['total']), right: true),
            c(_money(l['icmsBase']), right: true),
            c(_money(l['icmsValue']), right: true),
            c(_money(l['ipiValue']), right: true),
            c('${fmtNum(_n(l['icmsPercent']), 2)}% / ${fmtNum(_n(l['ipiPercent']), 2)}%', right: true),
          ],
        ),
    ],
  );

  final info = [_s(d['additionalInfo']), if (_s(d['statusMessage']).isNotEmpty) _s(d['statusMessage'])].where((e) => e.isNotEmpty).join('\n');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      build: (_) => [
        header,
        table,
        _title('DADOS ADICIONAIS'),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(3),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.4)),
          child: pw.Text(info.isEmpty ? ' ' : info, style: _val(7)),
        ),
      ],
      footer: (ctx) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Página ${ctx.pageNumber}/${ctx.pagesCount}', style: _val(6))),
    ),
  );
  return doc.save();
}

/// Fetches the issuer data, builds the DANFE of [d] (the document JSON from the API) and opens the print/save dialog.
Future<void> printDanfe(BuildContext context, ApiClient api, Map<String, dynamic> d) async {
  try {
    final issuer = await api.get('/api/fiscal/settings') as Map<String, dynamic>;
    final bytes = await buildDanfePdf(d, issuer);
    await Printing.layoutPdf(name: 'DANFE NF ${d['number']}', onLayout: (_) async => bytes, format: PdfPageFormat.a4);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao gerar o DANFE: ${friendlyError(e)}')));
  }
}
