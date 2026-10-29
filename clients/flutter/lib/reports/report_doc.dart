import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

enum ReportRowKind { normal, group, subtotal, total, section }

class ReportRow {
  const ReportRow(this.cells, [this.kind = ReportRowKind.normal]);

  final List<String> cells;
  final ReportRowKind kind;
}

/// A flat, printable table. The same document drives the on-screen view, CSV and PDF.
class ReportDoc {
  const ReportDoc({required this.title, required this.filters, required this.headers, required this.numeric, required this.rows, this.notes = const [], this.flex});

  final String title;
  final List<String> filters;
  final List<String> headers;
  final List<bool> numeric;
  final List<ReportRow> rows;
  final List<String> notes;
  final List<int>? flex;

  String get fileBase => title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

  /// Semicolon separated with a UTF-8 BOM, which Excel (pt-BR) opens directly.
  Uint8List toCsv() {
    String esc(String s) => s.contains(RegExp(r'[;"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    final b = StringBuffer('﻿')
      ..writeln(esc(title))
      ..writeln(esc(filters.join(' | ')))
      ..writeln(headers.map(esc).join(';'));
    for (final r in rows) {
      final cells = r.kind == ReportRowKind.normal || r.cells.length == headers.length ? r.cells : [...r.cells, ...List.filled(headers.length - r.cells.length, '')];
      b.writeln(cells.map(esc).join(';'));
    }
    for (final n in notes) {
      b.writeln(esc(n));
    }
    return Uint8List.fromList(utf8.encode(b.toString()));
  }

  Future<Uint8List> toPdf() async {
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf')),
      bold: pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf')),
    );
    final doc = pw.Document(title: title, theme: theme);
    final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8);
    const base = pw.TextStyle(fontSize: 8);
    final widths = <int, pw.TableColumnWidth>{for (var i = 0; i < headers.length; i++) i: pw.FlexColumnWidth((flex?[i] ?? 1).toDouble())};
    pw.Widget cell(String t, int i, pw.TextStyle s) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Text(t, style: s, textAlign: numeric[i] ? pw.TextAlign.right : pw.TextAlign.left, maxLines: 2),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            if (filters.isNotEmpty) pw.Text(filters.join('   |   '), style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (c) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Página ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 7))),
        build: (_) => [
          pw.Table(
            columnWidths: widths,
            border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.3)),
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [for (var i = 0; i < headers.length; i++) cell(headers[i], i, bold)]),
              for (final r in rows)
                if (r.kind == ReportRowKind.group || r.kind == ReportRowKind.section)
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [for (var i = 0; i < headers.length; i++) cell(i == 0 ? r.cells.first : '', i, bold)],
                  )
                else
                  pw.TableRow(
                    decoration: r.kind == ReportRowKind.total ? const pw.BoxDecoration(color: PdfColors.grey300) : null,
                    children: [for (var i = 0; i < headers.length; i++) cell(i < r.cells.length ? r.cells[i] : '', i, r.kind == ReportRowKind.normal ? base : bold)],
                  ),
            ],
          ),
          if (notes.isNotEmpty) pw.SizedBox(height: 8),
          for (final n in notes) pw.Text(n, style: const pw.TextStyle(fontSize: 7)),
        ],
      ),
    );
    return doc.save();
  }
}

/// Export / print / send actions for a [ReportDoc].
class ReportActions extends StatelessWidget {
  const ReportActions({super.key, required this.doc, this.enabled = true});

  final ReportDoc Function() doc;
  final bool enabled;

  void _toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(BuildContext c, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (c.mounted) _toast(c, 'Falha: $e');
    }
  }

  Future<void> _save(BuildContext c, String ext, Future<Uint8List> Function(ReportDoc d) bytes, String mime) => _run(c, () async {
    final d = doc();
    final saved = await FilePicker.saveFile(fileName: '${d.fileBase}.$ext', bytes: await bytes(d), mimeType: mime, dialogTitle: 'Salvar relatório');
    if (saved != null && c.mounted) _toast(c, 'Arquivo salvo');
  });

  Future<void> _print(BuildContext c) => _run(c, () async {
    final d = doc();
    await Printing.layoutPdf(name: d.title, onLayout: (_) => d.toPdf(), format: PdfPageFormat.a4.landscape);
  });

  Future<void> _send(BuildContext c) => _run(c, () async {
    final d = doc();
    final pdf = await d.toPdf();
    await SharePlus.instance.share(
      ShareParams(subject: d.title, text: '${d.title}\n${d.filters.join('\n')}', files: [XFile.fromData(pdf, name: '${d.fileBase}.pdf', mimeType: 'application/pdf')], fileNameOverrides: ['${d.fileBase}.pdf']),
    );
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      PopupMenuButton<String>(
        enabled: enabled,
        tooltip: 'Exportar',
        onSelected: (v) => v == 'pdf' ? _save(context, 'pdf', (d) => d.toPdf(), 'application/pdf') : _save(context, 'csv', (d) async => d.toCsv(), 'text/csv'),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('PDF'), dense: true)),
          PopupMenuItem(value: 'csv', child: ListTile(leading: Icon(Icons.table_chart_outlined), title: Text('Excel (CSV)'), dense: true)),
        ],
        child: IgnorePointer(child: OutlinedButton.icon(onPressed: enabled ? () {} : null, icon: const Icon(Icons.download_outlined), label: const Text('Exportar'))),
      ),
      OutlinedButton.icon(onPressed: enabled ? () => _print(context) : null, icon: const Icon(Icons.print_outlined), label: const Text('Imprimir')),
      OutlinedButton.icon(onPressed: enabled ? () => _send(context) : null, icon: const Icon(Icons.send_outlined), label: const Text('Enviar')),
    ],
  );
}
