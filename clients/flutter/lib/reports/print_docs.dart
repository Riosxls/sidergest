import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../screens/customers.dart' show fmtDocument;

// Dados da empresa no cabeçalho dos documentos. Ajustar quando o cadastro da empresa existir no sistema.
const _companyName = 'EBT';
const _companyCnpj = 'CNPJ: 00.000.000/0000-00';
const _companyAddress = 'Endereço: a definir';

const _generalConditions =
    'Preços sujeitos a confirmação na data do pedido. Impostos conforme legislação vigente. '
    'Prazo de entrega contado a partir da confirmação do pedido e da aprovação de desenhos, quando aplicável.';

Future<pw.ThemeData> _theme() async => pw.ThemeData.withFont(
  base: pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf')),
  bold: pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf')),
);

pw.TextStyle _b([double size = 9]) => pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: size);
pw.TextStyle _n([double size = 9]) => pw.TextStyle(fontSize: size);

String _s(Object? v) => v == null ? '' : '$v';

pw.Widget _header(String docTitle, String reference) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 56,
          height: 56,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600)),
          child: pw.Text('LOGO', style: _n(9)),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [pw.Text(_companyName, style: _b(14)), pw.Text(_companyCnpj, style: _n(8)), pw.Text(_companyAddress, style: _n(8))],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [pw.Text(docTitle, style: _b(13)), pw.Text(reference, style: _b(16))],
        ),
      ],
    ),
    pw.Divider(thickness: 1),
  ],
);

pw.Widget _box(String title, List<(String, String)> fields) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.all(6),
  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: 0.5)),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title, style: _b(9)),
      pw.SizedBox(height: 3),
      pw.Wrap(
        spacing: 18,
        runSpacing: 3,
        children: [
          for (final (k, v) in fields)
            if (v.isNotEmpty) pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: '$k: ', style: _b(8)), pw.TextSpan(text: v, style: _n(8))])),
        ],
      ),
    ],
  ),
);

pw.Widget _cell(String t, {bool bold = false, bool right = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
  child: pw.Text(t, style: bold ? _b(8) : _n(8), textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
);

pw.Widget _table(List<String> headers, List<List<String>> rows, {required List<num> flex, Set<int> right = const {}}) => pw.Table(
  columnWidths: {for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i].toDouble())},
  border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.3), bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.5)),
  children: [
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [for (var i = 0; i < headers.length; i++) _cell(headers[i], bold: true, right: right.contains(i))],
    ),
    for (final r in rows) pw.TableRow(children: [for (var i = 0; i < r.length; i++) _cell(r[i], right: right.contains(i))]),
  ],
);

pw.Widget _totals(List<(String, String)> rows) => pw.Align(
  alignment: pw.Alignment.centerRight,
  child: pw.SizedBox(
    width: 220,
    child: pw.Column(
      children: [
        for (final (i, (k, v)) in rows.indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [pw.Text(k, style: i == rows.length - 1 ? _b(10) : _n(9)), pw.Text(v, style: i == rows.length - 1 ? _b(10) : _n(9))],
            ),
          ),
      ],
    ),
  ),
);

pw.Widget _text(String title, String body) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [pw.SizedBox(height: 8), pw.Text(title, style: _b(9)), pw.SizedBox(height: 2), pw.Text(body, style: _n(8))],
);

pw.Widget _footer(pw.Context c) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Página ${c.pageNumber}/${c.pagesCount}', style: _n(7)));

Future<Uint8List> _build(String title, List<pw.Widget> Function() body, {PdfPageFormat? format, pw.Widget Function(pw.Context)? header}) async {
  final doc = pw.Document(title: title, theme: await _theme());
  doc.addPage(pw.MultiPage(pageFormat: format ?? PdfPageFormat.a4, margin: const pw.EdgeInsets.all(28), footer: _footer, header: header, build: (_) => body()));
  return doc.save();
}

Future<Map<String, dynamic>?> _customer(ApiClient api, Object? id) async {
  if (id == null) return null;
  try {
    return await api.get('/api/customers/$id') as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

String _customerDocument(Map<String, dynamic>? c) {
  final company = c?['company'] as Map<String, dynamic>?;
  final doc = fmtDocument(company?['document']);
  return doc.isEmpty ? '' : doc;
}

List<List<String>> _itemRows(List<Map<String, dynamic>> lines) => [
  for (final l in lines)
    [
      _s(l['sequence']),
      '${l['productCode']}${l['customerPartNumber'] == null ? '' : ' (${l['customerPartNumber']})'}',
      _s(l['description']),
      fmt(l['quantity']),
      _s(l['unit']),
      fmtNum(l['unitPrice'], 4),
      fmt(l['ipiPercent']),
      fmt(l['icmsPercent']),
      fmtNum(l['total']),
    ],
];

const _itemHeaders = ['Item', 'Produto', 'Descrição', 'Qtd.', 'Un.', 'Preço unit.', 'IPI %', 'ICMS %', 'Valor estimado'];
const List<num> _itemFlex = [0.6, 1.8, 3.4, 1, 0.7, 1.4, 0.8, 0.9, 1.6];
const _itemRight = {3, 5, 6, 7, 8};

/// Orçamento (PROP N).
Future<Uint8List> buildQuotePdf(ApiClient api, Map<String, dynamic> q) async {
  final customer = await _customer(api, q['customerId']);
  final t = q['totals'] as Map<String, dynamic>;
  final lines = (q['lines'] as List).cast<Map<String, dynamic>>();
  final date = q['sentAt'] ?? q['createdAt'];
  return _build('Orçamento ${q['reference']}', () => [
    _box('Cliente', [
      ('Nome', _s(q['customerName'])),
      ('CNPJ', _customerDocument(customer)),
      ('Endereço de entrega', _s(q['addressText'])),
    ]),
    pw.SizedBox(height: 6),
    _box('Orçamento', [
      ('Nº', _s(q['reference'])),
      ('Data', date == null ? '' : fmtDay(_s(date).split('T').first)),
      ('Validade', q['validUntil'] != null ? fmtDay(q['validUntil']) : '${q['validityDays']} dias após o envio'),
      ('Prazo', fmt(q['paymentTermName'] ?? q['customPaymentTerm'])),
      ('Frete', freightTerms[q['freight']] ?? fmt(q['freight'])),
      ('Contato', [q['contactName'], q['contactEmail']].whereType<String>().join(' · ')),
      ('Ref. do cliente', fmt(q['customerReference'])),
    ]),
    pw.SizedBox(height: 8),
    _table(_itemHeaders, _itemRows(lines), flex: _itemFlex, right: _itemRight),
    pw.SizedBox(height: 8),
    _totals([('Total dos produtos', fmtMoney(t['products'])), ('IPI', fmtMoney(t['ipi'])), ('Total do orçamento', fmtMoney(t['total']))]),
    if (_s(q['notes']).isNotEmpty) _text('Observações', _s(q['notes'])),
    _text('Condições gerais', _s(q['conditions']).isNotEmpty ? _s(q['conditions']) : _generalConditions),
  ], header: (_) => _header('Orçamento', _s(q['reference'])));
}

// ---- Formulários internos (modelos oficiais: Pedido Interno de Venda e Ordem de Fabricação) ----

const _ink = PdfColors.black;
const _blue = PdfColor.fromInt(0xFF1F3864);
const _sectionFill = PdfColor.fromInt(0xFFDCE6F1);
const _refRed = PdfColor.fromInt(0xFFFF0000);
const _checkYellow = PdfColor.fromInt(0xFFFFFF00);

pw.TextStyle _t(double size, {bool bold = false, PdfColor color = _ink}) => pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color);

const _line = pw.BorderSide(color: _ink, width: 1);
const _under = pw.BoxDecoration(border: pw.Border(bottom: _line));
const _leftUnder = pw.BoxDecoration(border: pw.Border(left: _line, bottom: _line));

pw.Widget _frame(List<pw.Widget> children) => pw.Container(
  decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.5)),
  child: pw.Column(children: children),
);

/// Linha de largura total com borda inferior; `cells` é uma lista de (flex, widget).
pw.Widget _formRow(List<(int, pw.Widget)> cells, {double? height, bool lastRow = false}) => pw.Container(
  height: height ?? 16,
  decoration: lastRow ? null : _under,
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      for (final (i, (flex, w)) in cells.indexed)
        pw.Expanded(
          flex: flex,
          child: pw.Container(
            decoration: i == 0 ? null : const pw.BoxDecoration(border: pw.Border(left: _line)),
            padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            alignment: pw.Alignment.centerLeft,
            child: w,
          ),
        ),
    ],
  ),
);

pw.Widget _lbl(String label, [String value = '', double size = 8.5]) => pw.RichText(
  text: pw.TextSpan(
    children: [
      pw.TextSpan(text: label, style: _t(size, bold: true)),
      if (value.isNotEmpty) pw.TextSpan(text: ' $value', style: _t(size, bold: true, color: _blue)),
    ],
  ),
);

pw.Widget _centered(pw.Widget w) => pw.Center(child: w);

pw.Widget _sectionTitle(String t, {double size = 9, bool fill = false, bool bold = true}) => pw.Container(
  width: double.infinity,
  alignment: pw.Alignment.center,
  padding: const pw.EdgeInsets.symmetric(vertical: 2),
  decoration: pw.BoxDecoration(color: fill ? _sectionFill : null, border: const pw.Border(bottom: _line)),
  child: pw.Text(t, style: _t(size, bold: bold)),
);

pw.Widget _checkBox(bool checked, {double w = 22, double h = 12}) => pw.Container(
  width: w,
  height: h,
  alignment: pw.Alignment.center,
  decoration: pw.BoxDecoration(color: checked ? _checkYellow : null, border: pw.Border.all(color: _ink, width: 0.8)),
  child: checked ? pw.Text('X', style: _t(9, bold: true)) : null,
);

pw.Widget _checkItem(String label, bool checked, {bool boxFirst = true, double size = 8.5}) {
  final box = _checkBox(checked);
  final text = pw.Text(label, style: _t(size, bold: true));
  return pw.Row(mainAxisSize: pw.MainAxisSize.min, children: boxFirst ? [box, pw.SizedBox(width: 4), text] : [text, pw.SizedBox(width: 4), box]);
}

pw.Widget _titleBar(String title, String reference) => pw.Container(
  height: 38,
  decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.5)),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Expanded(child: pw.Center(child: pw.Text(title, style: _t(15, bold: true)))),
      pw.Container(
        width: 100,
        alignment: pw.Alignment.center,
        decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: _ink, width: 1.5))),
        child: pw.Text(reference, style: _t(14, color: _refRed)),
      ),
    ],
  ),
);

pw.Widget _checkLabel(bool checked, String label) => pw.Row(children: [_checkBox(checked), pw.SizedBox(width: 6), pw.Text(label, style: _t(8.5, bold: true))]);

pw.Widget _codeLabel(String label, String value) => pw.Row(children: [pw.Text('$label  ', style: _t(8.5, bold: true)), pw.Text(value, style: _t(9, bold: true, color: _blue))]);

pw.Widget _identBox({required String productCode, required String customerCode}) => _frame([
  _formRow([(1, _checkLabel(false, 'CLIENTE NOVO')), (1, _checkLabel(true, 'CLIENTE CADASTRADO')), (1, _codeLabel('CÓD. PRODUTO:', productCode))], height: 26),
  _formRow([(1, _checkLabel(false, 'ITEM NOVO')), (1, _checkLabel(false, 'ITEM JÁ FORNECIDO')), (1, _codeLabel('CÓD. CLIENTE:', customerCode))], height: 26, lastRow: true),
]);

pw.Widget _orderedBy() => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 20),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [pw.Text('PEDIDO POR:', style: _t(8.5, bold: true)), _checkItem('E-MAIL', false), _checkItem('FAX', false), _checkItem('VERBAL', false)],
  ),
);

/// Endereço, CNPJ, IE e contato do cliente (preferindo o cadastro da empresa, depois o endereço padrão).
class _CustomerBlock {
  _CustomerBlock(this.name, Map<String, dynamic>? c, String addressText) {
    final co = c?['company'] as Map<String, dynamic>?;
    final ad = c?['defaultAddress'] as Map<String, dynamic>?;
    String pick(String key) => _s(co?[key]).isNotEmpty ? _s(co?[key]) : _s(ad?[key]);
    final street = pick('street');
    address = street.isEmpty ? addressText : [street, pick('number')].where((e) => e.isNotEmpty).join(', ');
    district = pick('district');
    city = pick('city');
    uf = pick('uf');
    zip = pick('zipCode');
    cnpj = fmtDocument(co?['document'] ?? ad?['document']);
    ie = pick('stateRegistration');
    contact = _s(co?['contact']).isNotEmpty ? _s(co?['contact']) : _s(ad?['buyer']);
    phone = pick('phone');
    email = pick('email');
    code = _s(c?['legacyCode']).isNotEmpty ? _s(c?['legacyCode']) : _s(c?['id']);
  }

  final String name;
  late final String address, district, city, uf, zip, cnpj, ie, contact, phone, email, code;
}

pw.Widget _customerBox(_CustomerBlock c) => _frame([
  _formRow([(1, _lbl('CLIENTE:', c.name))]),
  _formRow([(1, _lbl('END:', c.address))]),
  _formRow([(1, _lbl('BAIRRO:', c.district)), (1, _lbl('MUNÍCIPIO:', c.city))]),
  _formRow([(1, _lbl('CEP:', c.zip)), (1, _lbl('ESTADO:', c.uf))]),
  _formRow([(1, _lbl('CNPJ:', c.cnpj)), (1, _lbl('I.E:', c.ie))]),
  _formRow([(1, _lbl('CONTATO:', c.contact)), (1, _lbl('TEL/ FAX:', c.phone))]),
  _formRow([(1, _lbl('E-MAIL:', c.email))], lastRow: true),
]);

pw.Widget _specBox({required String dimensions, required String quantity, required String material, required String delivery, required String notes}) => _frame([
  _sectionTitle('ESPECIFICAÇÃO', size: 10),
  _formRow([(1, _lbl('DIMENSÕES DO TUBO (MM):', dimensions)), (1, _lbl('QUANTIDADE (KG/PÇ):', quantity))]),
  _formRow([(1, _lbl('ESPECIFICAÇÃO DO MATERIAL:', material)), (1, _lbl('DATA DE ENTREGA:', delivery))]),
  _formRow([(1, _lbl('OBSERVAÇÕES:', notes))], lastRow: true),
]);

Future<Uint8List> _forms(String title, List<pw.Widget> pages) async {
  final doc = pw.Document(title: title, theme: await _theme());
  for (final p in pages) {
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28), build: (_) => p));
  }
  return doc.save();
}

String _qty(num q, String unit) => '${fmtNum(q, q == q.roundToDouble() ? 0 : 3)} $unit'.trim();

/// Pedido interno de venda (PV N). Uma página por item, conforme o modelo.
Future<Uint8List> buildSalesOrderPdf(ApiClient api, Map<String, dynamic> o) async {
  final customer = await _customer(api, o['customerId']);
  final c = _CustomerBlock(_s(o['customerName']), customer, _s(o['addressText']));
  final lines = (o['lines'] as List).cast<Map<String, dynamic>>();
  final created = _s(o['createdAt']).split('T').first;
  final term = _s(o['paymentTermName'] ?? o['customPaymentTerm']);
  final freight = _s(o['freight']);
  final po = _s(o['customerPo']);
  final notes = [if (po.isNotEmpty) 'PEDIDO Nº $po', if (_s(o['notes']).isNotEmpty) _s(o['notes'])].join(' - ');
  final pages = <pw.Widget>[
    for (final l in lines)
      () {
        final qty = (l['quantity'] as num?) ?? 0;
        final price = (l['unitPrice'] as num?) ?? 0;
        final ipi = (l['ipiPercent'] as num?) ?? 0;
        final total = double.parse((qty * price * (1 + ipi / 100)).toStringAsFixed(2));
        final description = _s(l['description']).isNotEmpty ? _s(l['description']) : _s(l['productCode']);
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _titleBar('PEDIDO INTERNO DE VENDA', _s(o['reference'])),
            pw.SizedBox(height: 4),
            _identBox(productCode: _s(l['productCode']), customerCode: c.code),
            _orderedBy(),
            _customerBox(c),
            pw.SizedBox(height: 4),
            _specBox(dimensions: description, quantity: _qty(qty, _s(l['unit'])), material: _s(l['customerPartNumber']), delivery: fmtDay(l['dueDate']), notes: notes),
            pw.SizedBox(height: 4),
            _salesTerms(price: fmtMoney(price), perKg: _s(l['unit']).toUpperCase() == 'KG', icms: fmt(l['icmsPercent']), ipi: '${fmt(ipi)}%', total: fmtMoney(total), term: term),
            pw.SizedBox(height: 4),
            _freightBox(freight: freight, place: c.address),
            pw.SizedBox(height: 22),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 40),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(children: [pw.Text(created.isEmpty ? '' : fmtDay(created), style: _t(8.5, bold: true)), pw.Text('DATA', style: _t(8.5, bold: true))]),
                  pw.Text('ASSINATURA DO RESPONSÁVEL DE VENDAS', style: _t(8.5, bold: true)),
                ],
              ),
            ),
          ],
        );
      }(),
  ];
  return _forms('Pedido de venda ${o['reference']}', pages);
}

pw.Widget _salesTerms({required String price, required bool perKg, required String icms, required String ipi, required String total, required String term}) => pw.Container(
  decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.5)),
  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 40),
  child: pw.Column(
    children: [
      pw.Text('CONDIÇÕES DE VENDA', style: _t(10, bold: true)),
      pw.SizedBox(height: 8),
      pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.2)),
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text('PREÇO DE VENDA:', style: _t(8.5, bold: true)), pw.Text(price, style: _t(9, bold: true, color: _blue)), _checkItem('KG', perKg), _checkItem('PÇ', !perKg)],
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.2)),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('IMPOSTOS :', style: _t(8.5, bold: true)),
            pw.SizedBox(width: 12),
            pw.Column(children: [_lbl('ICMS:', icms), pw.SizedBox(height: 2), _lbl('I.P.I:', ipi)]),
          ],
        ),
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.2)),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Container(width: 110, height: 40, alignment: pw.Alignment.center, child: pw.Text('VALOR  TOTAL R\$', style: _t(8.5, bold: true))),
            pw.Container(
              width: 150,
              height: 40,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: _ink, width: 1.2))),
              child: pw.Text(total, style: _t(16, color: _blue)),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        width: double.infinity,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.2)),
        child: pw.Text('PRAZO DE PAGAMENTO: $term', style: _t(8.5, bold: true, color: _blue)),
      ),
      pw.SizedBox(height: 6),
    ],
  ),
);

pw.Widget _freightBox({required String freight, required String place}) => pw.Container(
  decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.5)),
  padding: const pw.EdgeInsets.fromLTRB(10, 4, 10, 6),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Center(child: pw.Text('FRETE', style: _t(10, bold: true))),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [pw.Text('CLIENTE RETIRA:   ', style: _t(8.5, bold: true)), _checkBox(freight == 'CustomerPickup', w: 30)]),
          pw.Column(
            children: [
              pw.Row(children: [_checkBox(freight == 'Cif', w: 30), pw.SizedBox(width: 8), pw.Text('ENTREGA POR NOSSA CONTA', style: _t(8.5, bold: true))]),
              pw.SizedBox(height: 3),
              pw.Text('LOCAL DE ENTREGA:', style: _t(8.5, bold: true)),
              pw.SizedBox(width: 200, child: pw.Text(place, style: _t(8.5, bold: true, color: _blue), textAlign: pw.TextAlign.center)),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text('TRANSPORTADORA:', style: _t(8.5, bold: true)),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text('CNPJ: ______________________________________________', style: _t(8.5, bold: true)), pw.Text('I.E: _________________________________', style: _t(8.5, bold: true))],
      ),
    ],
  ),
);

const _opFlex = [10, 36, 14, 11, 11, 18];

pw.Widget _opCell(pw.Widget child, int i, {double height = 17}) => pw.Expanded(
  flex: _opFlex[i],
  child: pw.Container(height: height, alignment: pw.Alignment.center, padding: const pw.EdgeInsets.symmetric(horizontal: 3), decoration: i == 0 ? _under : _leftUnder, child: child),
);

pw.Widget _opRow(List<pw.Widget> cells) => pw.Row(children: [for (final (i, w) in cells.indexed) _opCell(w, i)]);

String _mm(Object? v) => v is num ? fmtNum(v, v == v.roundToDouble() ? 0 : 2) : '';

/// Dimensões do tubo a partir do cadastro do produto (engenharia); sem medidas, usa o nome.
String _tubeDimensions(Map<String, dynamic>? p, String fallback) {
  if (p == null) return fallback;
  final size = p['shape'] == 'Rectangular' || p['shape'] == 1
      ? [_mm(p['widthMm']), _mm(p['heightMm'])].where((e) => e.isNotEmpty).join(' x ')
      : (_mm(p['diameterMm']).isEmpty ? '' : 'Ø ${_mm(p['diameterMm'])}');
  final parts = [size, _mm(p['thicknessMm']), _mm(p['lengthMm'])].where((e) => e.isNotEmpty).toList();
  return parts.isEmpty ? fallback : parts.join(' x ');
}

/// Especificação do material: matérias-primas da estrutura (BOM) da ordem.
String _materialSpec(List<Map<String, dynamic>> mats) =>
    mats.map((m) => _s(m['description']).isNotEmpty ? _s(m['description']) : _s(m['code'])).where((e) => e.isNotEmpty).toSet().join('; ');

/// Ordem de produção (OF N), conforme o modelo oficial.
Future<Uint8List> buildProductionOrderPdf(ApiClient api, Map<String, dynamic> o) async {
  final customer = await _customer(api, o['customerId']);
  final c = _CustomerBlock(_s(customer?['name']), customer, '');
  Map<String, dynamic>? product;
  try {
    product = await api.get('/api/products/${o['productId']}') as Map<String, dynamic>;
  } catch (_) {}
  final ops = (o['operations'] as List).cast<Map<String, dynamic>>();
  final mats = (o['materials'] as List).cast<Map<String, dynamic>>();
  final qty = (o['quantity'] as num?) ?? 0;
  final rawMaterial = mats.isEmpty ? '' : (_s(mats.first['description']).isNotEmpty ? _s(mats.first['description']) : _s(mats.first['code']));
  final blankRows = ops.length >= 7 ? 1 : 14 - ops.length * 2;
  final none = pw.SizedBox();
  pw.Widget small(String t) => pw.Text(t, style: _t(8.5));
  pw.Widget head(String t, {bool left = true, double? height, double? width}) => pw.Container(
    width: width,
    height: height,
    alignment: pw.Alignment.center,
    decoration: left ? _leftUnder : _under,
    child: pw.Text(t, style: _t(8, bold: true), textAlign: pw.TextAlign.center),
  );

  final page = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      _titleBar('ORDEM DE PRODUÇÃO', _s(o['customerPo']).isNotEmpty ? _s(o['customerPo']) : _s(o['reference'])),
      pw.SizedBox(height: 4),
      _identBox(productCode: _s(o['productCode']), customerCode: c.code),
      _orderedBy(),
      _customerBox(c),
      pw.SizedBox(height: 4),
      _specBox(dimensions: _tubeDimensions(product, _s(o['productName'])), quantity: _qty(qty, _s(o['productUnit'])), material: _materialSpec(mats), delivery: fmtDay(o['dueDate']), notes: _s(o['notes'])),
      _frame([
        _sectionTitle('PROCESSO', fill: true),
        _formRow([(1, _centered(small('Materia Prima:'))), (2, small(rawMaterial)), (1, _centered(small('Lote'))), (1, none)], height: 17),
        _formRow([(2, _lbl('Tubo Primario ( Perfila ):', '', 8)), (3, pw.Center(child: pw.Text(_s(o['primaryTube']), style: _t(9.5, bold: true))))], height: 20, lastRow: true),
      ]),
      pw.SizedBox(height: 4),
      _frame([
        _sectionTitle('PROCESSOS SECUNDÁRIOS', size: 8.5, fill: true),
        pw.Row(
          children: [
            pw.Expanded(flex: _opFlex[0], child: head('Nº Operação', left: false, height: 30)),
            pw.Expanded(flex: _opFlex[1], child: head('Descrição da Operação (mm)', height: 30)),
            pw.Expanded(flex: _opFlex[2], child: head('Requisitos/\nTolerância (mm)', height: 30)),
            pw.Expanded(
              flex: _opFlex[3] + _opFlex[4],
              child: pw.Column(children: [head('MEDIDAS', height: 15, width: double.infinity), pw.Row(children: [pw.Expanded(child: head('INICIO', height: 15)), pw.Expanded(child: head('FINAL', height: 15))])]),
            ),
            pw.Expanded(flex: _opFlex[5], child: pw.Column(children: [head('Recursos necessário', height: 15, width: double.infinity), head('Maq. / Ferramenta', height: 15, width: double.infinity)])),
          ],
        ),
        for (final op in ops) ...[
          _opRow([small(_s(op['sequence'])), small(_s(op['description'])), small(_s(op['tolerance'])), small(_s(op['measureStart'])), small(_s(op['measureEnd'])), small(op['external'] == true ? 'Terceiro' : _s(op['machineCode']))]),
          _opRow([none, none, none, none, none, none]),
        ],
        for (var i = 0; i < blankRows; i++) _opRow([none, none, none, none, none, none]),
      ]),
      pw.SizedBox(height: 4),
      _frame([
        pw.Container(
          width: double.infinity,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: const pw.BoxDecoration(color: _sectionFill, border: pw.Border(bottom: _line)),
          child: pw.Text('SOLICITAÇÃO DE EMISSÃO DE NOTA ( S.E.N.F)', style: _t(11, bold: false)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          child: pw.Column(
            children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [_checkItem('FATURAMENTO', false, size: 10), _checkItem('DEVOLUÇÃO', false, size: 10), _checkItem('BENEFICIAMENTO', false, size: 10)]),
              pw.SizedBox(height: 4),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [_checkItem('SISTEMISTA', false, size: 10), pw.SizedBox(width: 40), _checkItem('SPOT', false, size: 10)]),
            ],
          ),
        ),
        pw.Container(decoration: const pw.BoxDecoration(border: pw.Border(top: _line)), child: pw.SizedBox(width: double.infinity)),
        _formRow([
          (2, _centered(pw.Text('QUANTIDADE', style: _t(8, bold: true)))),
          (2, none),
          (2, _centered(pw.Text('UNIDADE', style: _t(8, bold: true)))),
          (1, none),
          (2, _centered(pw.Text('VOLUMES', style: _t(8, bold: true)))),
          (1, none),
        ], height: 17, lastRow: true),
      ]),
      pw.SizedBox(height: 4),
      _frame([
        pw.Container(
          width: double.infinity,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: const pw.BoxDecoration(color: _sectionFill, border: pw.Border(bottom: _line)),
          child: pw.Text('INSPEÇÃO FINAL', style: _t(11)),
        ),
        _formRow([
          (3, _centered(pw.Text('ESPECIFICAÇÕES:\n(CONFORME PI E ANÁLISE DE VIABILIDADE)', style: _t(5.5), textAlign: pw.TextAlign.center))),
          (1, _centered(pw.Text('MIN', style: _t(8)))),
          (1, _centered(pw.Text('MAX', style: _t(8)))),
          (3, _centered(pw.Text('ESPECIFICAÇÕES:\n(CONFORME PI E ANÁLISE DE VIABILIDADE)', style: _t(5.5), textAlign: pw.TextAlign.center))),
          (1, _centered(pw.Text('MIN', style: _t(8)))),
          (1, _centered(pw.Text('MAX', style: _t(8)))),
        ], height: 26),
        _formRow([(3, _centered(small('DIAM EXT:'))), (1, none), (1, none), (3, _centered(small('ESPESSURA:'))), (1, none), (1, none)], height: 18),
        _formRow([(3, _centered(small('DIAM INT:(se solicitado)'))), (1, none), (1, none), (3, _centered(small('COMPRIMENTO:'))), (1, none), (1, none)], height: 18),
        _formRow([(2, _centered(small('DATA:'))), (3, _centered(small('/          /'))), (3, _centered(small('RESPONSAVEL:'))), (2, none)], height: 18),
        _formRow([
          (2, _centered(small('SITUAÇÃO'))),
          (2, pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [small('APROVADO'), pw.SizedBox(width: 4), _checkBox(false, w: 26)])),
          (2, pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [small('REPROVADO'), pw.SizedBox(width: 4), _checkBox(false, w: 26)])),
          (2, small('RNC:')),
        ], height: 20, lastRow: true),
      ]),
    ],
  );
  return _forms('Ordem de fabricação ${o['reference']}', [page]);
}

/// App bar print button shared by the three detail screens.
class PrintButton extends StatelessWidget {
  const PrintButton({super.key, required this.name, required this.builder, this.enabled = true, this.tooltip = 'Imprimir'});

  final String name;
  final Future<Uint8List> Function() builder;
  final bool enabled;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: const Icon(Icons.print_outlined),
    onPressed: enabled
        ? () async {
            try {
              final bytes = await builder();
              await Printing.layoutPdf(name: name, onLayout: (_) async => bytes, format: PdfPageFormat.a4);
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao imprimir: $e')));
            }
          }
        : null,
  );
}
