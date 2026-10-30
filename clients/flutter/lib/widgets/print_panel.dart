import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../reports/print_docs.dart' show printTheme;
import 'print_gate.dart';
import 'record_list.dart';

/// Sends a PDF to the print dialog, telling the user when it fails.
Future<void> printPdf(BuildContext context, String name, Future<Uint8List> Function() build, {String? doneKey}) async {
  try {
    final bytes = await build();
    await Printing.layoutPdf(name: name, onLayout: (_) async => bytes, format: PdfPageFormat.a4);
    await PrintLog.mark(doneKey);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao imprimir: $e')));
  }
}

/// The customer's purchase order as the customer sent it: a PDF prints as is, an image is placed on an A4 page and plain text is typeset.
/// Returns null when the file type cannot be printed from here (the user should download it instead).
Future<Uint8List?> customerOrderPdf({required String? fileName, Uint8List? file, String? text, required String title}) async {
  final name = (fileName ?? '').toLowerCase();
  if (file != null && name.endsWith('.pdf')) return file;
  final doc = pw.Document(title: title, theme: await printTheme());
  if (file != null && RegExp(r'\.(png|jpe?g|bmp|gif|webp)$').hasMatch(name)) {
    final image = pw.MemoryImage(file);
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(24), build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
    return doc.save();
  }
  if (file == null && (text ?? '').trim().isNotEmpty) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 10), pw.Text(text!.trim(), style: const pw.TextStyle(fontSize: 11))],
      ),
    );
    return doc.save();
  }
  return null;
}

/// One document of the purchase that has to be printed. [ready] false means it does not exist yet; [waiting] says what unlocks it.
class PrintDoc {
  const PrintDoc({required this.id, required this.label, this.detail, this.ready = true, this.waiting, this.onPrint});

  final String id;
  final String label;
  final String? detail;
  final bool ready;
  final String? waiting;
  final Future<void> Function()? onPrint;
}

/// "Documentos para imprimir": the five papers every purchase needs (customer PO, pedido interno de venda, ordem de fabricação, nota fiscal, certificado),
/// each with its print button, or with what is missing before it can be printed.
class PrintPanel extends StatelessWidget {
  const PrintPanel({super.key, required this.docs, this.title = 'Documentos para imprimir'});

  final List<PrintDoc> docs;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = docs.where((d) => d.ready).length;
    return Section(
      key: const ValueKey('print-panel'),
      title: '$title ($ready de ${docs.length} prontos)',
      child: Column(
        children: [
          for (final d in docs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(d.ready ? Icons.description_outlined : Icons.hourglass_empty, size: 22, color: d.ready ? cs.primary : cs.outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.label, style: TextStyle(fontWeight: FontWeight.w600, color: d.ready ? null : cs.outline)),
                        if (d.ready ? d.detail != null : d.waiting != null) Text(d.ready ? d.detail! : d.waiting!, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    key: ValueKey('doc-print-${d.id}'),
                    onPressed: d.ready ? d.onPrint : null,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimir'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
