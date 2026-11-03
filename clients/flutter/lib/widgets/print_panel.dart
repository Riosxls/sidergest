import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api.dart';
import '../reports/print_docs.dart' show printTheme;
import 'print_gate.dart';
import 'record_list.dart';

/// Sends a PDF to the print dialog, telling the user when it fails. Answers whether it was printed: a cancelled dialog or an error answers false
/// and the paper is not marked as handled.
Future<bool> printPdf(BuildContext context, String name, Future<Uint8List> Function() build, {String? doneKey}) async {
  try {
    final bytes = await build();
    final printed = await Printing.layoutPdf(name: name, onLayout: (_) async => bytes, format: PdfPageFormat.a4);
    if (printed) await PrintLog.mark(doneKey);
    return printed;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao imprimir: ${friendlyError(e)}')));
    return false;
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
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
    return doc.save();
  }
  if (file == null && (text ?? '').trim().isNotEmpty) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Text(title, style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Text(text!.trim(), style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
    return doc.save();
  }
  return null;
}

/// One document of the purchase that has to be printed. [ready] false means it does not exist yet; [waiting] says what unlocks it.
class PrintDoc {
  const PrintDoc({required this.id, required this.label, this.detail, this.ready = true, this.waiting, this.onPrint, this.doneKey, this.notApplicable = false});

  final String id;
  final String label;
  final String? detail;
  final bool ready;
  final String? waiting;
  final Future<void> Function()? onPrint;

  /// The [PrintLog] key of this paper: when set, the panel says on which day it was printed or saved on this computer.
  final String? doneKey;

  /// The paper does not exist for this purchase and none is expected (waived certificate, order served from stock): shown as such, not as "waiting".
  final bool notApplicable;
}

/// "Documentos para imprimir": the five papers every purchase needs (customer PO, pedido interno de venda, ordem de fabricação, nota fiscal, certificado),
/// each with its print button, or with what is missing before it can be printed. The header folds the list away.
class PrintPanel extends StatefulWidget {
  const PrintPanel({super.key, required this.docs, this.title = 'Documentos para imprimir', this.initiallyOpen = true});

  final List<PrintDoc> docs;
  final String title;
  final bool initiallyOpen;

  @override
  State<PrintPanel> createState() => _PrintPanelState();
}

class _PrintPanelState extends State<PrintPanel> {
  late bool _open = widget.initiallyOpen;
  final _done = <String, DateTime>{};

  @override
  void initState() {
    super.initState();
    _loadDays();
  }

  @override
  void didUpdateWidget(PrintPanel old) {
    super.didUpdateWidget(old);
    _loadDays();
  }

  /// The day each paper was handled; read again when the list changes (a print right here rebuilds the screen).
  Future<void> _loadDays() async {
    final found = <String, DateTime>{};
    for (final d in widget.docs) {
      final key = d.doneKey;
      if (key == null) continue;
      final day = await PrintLog.doneOn(key);
      if (day != null) found[key] = day;
    }
    if (!mounted || _same(found)) return;
    setState(() {
      _done
        ..clear()
        ..addAll(found);
    });
  }

  bool _same(Map<String, DateTime> found) => found.length == _done.length && found.entries.every((e) => _done[e.key] == e.value);

  static String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final docs = widget.docs;
    final ready = docs.where((d) => d.ready).length;
    final printed = docs.where((d) => d.doneKey != null && _done.containsKey(d.doneKey)).length;
    return Section(
      key: const ValueKey('print-panel'),
      title: '${widget.title} ($ready de ${docs.length} prontos${printed > 0 ? ' · $printed impressos' : ''})',
      actions: [
        IconButton(
          key: const ValueKey('print-panel-toggle'),
          tooltip: _open ? 'Recolher documentos' : 'Mostrar documentos',
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
        ),
      ],
      child: !_open
          ? const SizedBox.shrink()
          : Column(
              children: [
                for (final d in docs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(
                          d.ready ? Icons.description_outlined : (d.notApplicable ? Icons.remove_circle_outline : Icons.hourglass_empty),
                          size: 22,
                          color: d.ready ? cs.primary : cs.outline,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.label,
                                style: TextStyle(fontWeight: FontWeight.w600, color: d.ready ? null : cs.outline),
                              ),
                              if (d.ready ? d.detail != null : d.waiting != null)
                                Text(d.ready ? d.detail! : d.waiting!, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                              if (d.ready && d.doneKey != null && _done[d.doneKey] != null)
                                Text(
                                  'Impresso em ${_day(_done[d.doneKey]!)}',
                                  key: ValueKey('doc-done-${d.id}'),
                                  style: TextStyle(fontSize: 12.5, color: cs.primary),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          key: ValueKey('doc-print-${d.id}'),
                          onPressed: d.ready && d.onPrint != null
                              ? () async {
                                  await d.onPrint!();
                                  if (mounted) await _loadDays();
                                }
                              : null,
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
