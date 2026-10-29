import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../entities.dart';

/// Letterhead of each company, as printed on the paper certificates.
const _letterhead = {
  'EBT': (
    'EBT IND. E COM. DE PRODUTOS METALÚRGICOS LTDA',
    'Av. Dona Cesária Camargo de Oliveira, n° 321 - Jd. Vista Alegre - Embu das Artes/SP CEP: 06807-320',
    'Tel. (11) 4241-4436',
  ),
  'BST': ('BST Ind e Com de Produtos Metalurgicos Ltda.', 'Rua Antonio da Silva Leite,175 Anexo 2 Vila Nova Parada São Paulo-SP', 'Tel. (11) 4241-4436'),
};

pw.TextStyle _b([double size = 9]) => pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: size);
pw.TextStyle _n([double size = 9]) => pw.TextStyle(fontSize: size);

String _s(Object? v) => v == null ? '' : '$v'.trim();
String _dash(Object? v) => _s(v).isEmpty ? '-' : _s(v);

pw.Widget _cell(String t, {bool bold = false, pw.Alignment align = pw.Alignment.centerLeft, PdfColor? fill, double size = 8.5}) => pw.Container(
  color: fill,
  alignment: align,
  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
  child: pw.Text(t, style: bold ? _b(size) : _n(size)),
);

pw.Widget _titleBar(String t) => pw.Container(
  width: double.infinity,
  color: PdfColors.grey300,
  padding: const pw.EdgeInsets.symmetric(vertical: 3),
  alignment: pw.Alignment.center,
  child: pw.Text(t, style: _b(9.5)),
);

pw.Widget _grid(List<String> headers, List<List<String>> rows, {List<double>? flex}) => pw.Table(
  border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
  columnWidths: {for (var i = 0; i < headers.length; i++) i: pw.FlexColumnWidth(flex?[i] ?? 1)},
  children: [
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [for (var i = 0; i < headers.length; i++) _cell(headers[i], bold: true, align: i == 0 ? pw.Alignment.centerLeft : pw.Alignment.center)],
    ),
    for (final r in rows)
      pw.TableRow(
        children: [for (var i = 0; i < r.length; i++) _cell(r[i], bold: i == 0, align: i == 0 ? pw.Alignment.centerLeft : pw.Alignment.center)],
      ),
  ],
);

pw.Widget _field(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(width: 105, child: pw.Text(label, style: _b(9))),
      pw.Expanded(child: pw.Text(value, style: _n(9))),
    ],
  ),
);

/// Quality certificate in the layout of the spreadsheets used until now (one A4 page).
Future<Uint8List> buildCertificatePdf(Map<String, dynamic> c) async {
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf')),
  );
  final measures = (c['measures'] as List).cast<Map<String, dynamic>>();
  List<List<String>> rows(String kind) => [
    for (final m in measures.where((m) => m['kind'] == kind)) [_s(m['name']), _dash(m['specified']), _dash(m['found'])],
  ];
  final (company, address, phone) = _letterhead[c['company']] ?? _letterhead['EBT']!;
  final qty = '${fmt(c['quantity'])} ${_s(c['unit'])}'.trim();
  final nf = _s(c['effectiveInvoiceNumber']);
  final draft = c['status'] == 'Draft';
  final cancelled = c['status'] == 'Cancelled';

  final doc = pw.Document(theme: theme, title: 'Certificado de qualidade ${c['reference']}');
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Stack(
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey700, width: 0.8)),
                padding: const pw.EdgeInsets.all(8),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(child: pw.Center(child: pw.Text('CERTIFICADO DE QUALIDADE', style: _b(15)))),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [pw.Text('Nº: ${c['reference']}', style: _b(11)), pw.SizedBox(height: 3), pw.Text(fmtDay(c['issueDate']), style: _n(10))],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              _titleBar('Dados do Produto'),
              pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.5)),
                padding: const pw.EdgeInsets.all(6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _field('NF.:', nf),
                    _field('Nº Pedido:', _s(c['customerPo'])),
                    _field('Lote MP:', _s(c['rawMaterialLot'])),
                    _field('Quantidade:', qty),
                    _field('N° do Produto:', _s(c['productCode'])),
                    _field('Descrição:', _s(c['description'])),
                    _field('Código Cliente:', _s(c['customerPartNumber'])),
                    _field('Descrição Cliente:', _s(c['customerPartDescription'])),
                    _field('Cliente:', _s(c['customerName'])),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [_titleBar('Composição Química'), _grid(['%', 'Especif.', 'Encontr.'], rows('Chemical'), flex: [0.8, 1.4, 1.2])],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        _titleBar('Dimensional'),
                        _grid(['mm', 'Especif.', 'Encontr.'], rows('Dimensional'), flex: [1.2, 1.2, 1.4]),
                        pw.SizedBox(height: 8),
                        _titleBar('Ensaios Mecânicos'),
                        _grid(['Limites de Resistência', 'Especificado', 'Encontrado'], rows('Mechanical'), flex: [1.5, 1.2, 1.2]),
                        pw.SizedBox(height: 8),
                        _titleBar('Dureza'),
                        pw.Container(
                          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.5)),
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          alignment: pw.Alignment.center,
                          child: pw.Text(_dash(c['hardness']), style: _n(9)),
                        ),
                        pw.SizedBox(height: 8),
                        _titleBar('Acabamento Superficial'),
                        pw.Container(
                          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.5)),
                          padding: const pw.EdgeInsets.all(4),
                          alignment: pw.Alignment.center,
                          child: pw.Text(_s(c['finish']), style: _n(8.5), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.5)),
                padding: const pw.EdgeInsets.all(6),
                constraints: const pw.BoxConstraints(minHeight: 60),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [pw.Text('Obs.:', style: _b(9)), if (_s(c['notes']).isNotEmpty) pw.Text(_s(c['notes']), style: _n(9))],
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('Aprovação / Visto:', style: _b(9)),
                  pw.SizedBox(width: 12),
                  pw.Column(
                    children: [
                      pw.SizedBox(height: 18, width: 190, child: pw.Center(child: pw.Text(_s(c['approvedBy']), style: _n(9)))),
                      pw.Container(width: 190, height: 0.6, color: PdfColors.black),
                      pw.SizedBox(height: 2),
                      pw.Text('Qualidade', style: _n(8.5)),
                      pw.Text('(Nome / Setor)', style: _n(7.5)),
                    ],
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Divider(thickness: 0.6),
              pw.Center(child: pw.Text(company, style: _b(9))),
              pw.Center(child: pw.Text(address, style: _n(8))),
              pw.Center(child: pw.Text(phone, style: _n(8))),
            ],
          ),
          if (draft || cancelled)
            pw.Center(
              child: pw.Transform.rotateBox(
                angle: 0.6,
                child: pw.Text(
                  cancelled ? 'CANCELADO' : 'RASCUNHO',
                  style: pw.TextStyle(fontSize: 80, fontWeight: pw.FontWeight.bold, color: PdfColor(0.85, 0.85, 0.85, 0.6)),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  return doc.save();
}
