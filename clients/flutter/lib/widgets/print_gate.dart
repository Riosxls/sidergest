import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../prefs.dart';

/// Remembers, on this computer, which papers were already printed or downloaded (or deliberately skipped), so the flow only asks once.
class PrintLog {
  static const _key = 'printed-docs';

  static Future<bool> isDone(String doc) async {
    try {
      return ((await SharedPreferences.getInstance()).getStringList(_key) ?? const []).contains(doc);
    } catch (e) {
      debugPrint('print_gate: lookup failed, using fallback: $e');
      return false;
    }
  }

  /// How many papers this computer remembers as handled.
  static Future<int> count() async {
    try {
      return ((await SharedPreferences.getInstance()).getStringList(_key) ?? const []).length;
    } catch (e) {
      debugPrint('print_gate: lookup failed, using fallback: $e');
      return 0;
    }
  }

  /// Forgets everything, so the flow asks about each paper again.
  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (e) {
      debugPrint('print_gate: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  static const _atPrefix = 'printed-at:';

  /// The day a paper was marked as handled on this computer, or null when it was not (or an older version marked it).
  static Future<DateTime?> doneOn(String doc) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString('$_atPrefix$doc');
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (e) {
      debugPrint('print_gate: lookup failed, using fallback: $e');
      return null;
    }
  }

  static Future<void> mark(String? doc) async {
    if (doc == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? <String>[];
      if (!list.contains(doc)) await prefs.setStringList(_key, [...list.length > 500 ? list.sublist(list.length - 500) : list, doc]);
      await prefs.setString('$_atPrefix$doc', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('print_gate: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }
}

/// Saves generated PDF bytes through the file picker. Returns true when the user chose a place.
Future<bool> savePdf(BuildContext context, String fileName, Future<Uint8List> Function() build, {String? doneKey}) async {
  try {
    final bytes = await build();
    final saved = await FilePicker.saveFile(fileName: fileName, bytes: bytes, dialogTitle: 'Salvar $fileName');
    if (saved == null) return false;
    await PrintLog.mark(doneKey);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arquivo salvo')));
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao salvar: ${friendlyError(e)}')));
    return false;
  }
}

/// Before the flow moves on, offers to print or download the paper of the step that is ending, once. Returns true when the flow may go on
/// (printed, downloaded or ignored) and false when the user went back.
///
/// [onPrint] and [onDownload] may answer `false` (a `Future<bool>`) when nothing was printed or saved (the dialog was cancelled, the file picker closed, an error):
/// the paper then stays unmarked and the gate asks again next time. Callbacks that answer nothing count as done.
Future<bool> printGate(
  BuildContext context, {
  required String doneKey,
  required String title,
  required String message,
  required Future<void> Function() onPrint,
  Future<void> Function()? onDownload,
  String continueLabel = 'Ignorar e continuar',
}) async {
  if (!AppPrefs.printPrompts || await PrintLog.isDone(doneKey)) return true;
  if (!context.mounted) return false;
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.print_outlined),
      // "Voltar" abandons the whole flow, so it sits up in the title bar, apart from the three ways of going on.
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('gate-back'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: () => Navigator.pop(c),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.arrow_back, size: 18), SizedBox(width: 4), Text('Voltar')]),
            ),
          ),
          Text(title),
        ],
      ),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Text(message)),
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          key: const ValueKey('gate-skip'),
          style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.onSurfaceVariant),
          onPressed: () => Navigator.pop(c, 'skip'),
          child: Text(continueLabel),
        ),
        if (onDownload != null)
          OutlinedButton.icon(
            key: const ValueKey('gate-download'),
            onPressed: () => Navigator.pop(c, 'download'),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Baixar'),
          ),
        FilledButton.icon(
          key: const ValueKey('gate-print'),
          onPressed: () => Navigator.pop(c, 'print'),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Imprimir'),
        ),
      ],
    ),
  );
  if (choice == null) return false;
  Object? result;
  // The callbacks are typed void so closures need not return anything; one that does answer false (printPdf, savePdf) is heard here.
  if (choice == 'print') {
    result = await Future<Object?>.value(onPrint());
  } else if (choice == 'download') {
    result = await Future<Object?>.value(onDownload!());
  }
  // A cancelled print dialog or file picker did not handle the paper; "ignore" is a decision and does.
  if (result != false) await PrintLog.mark(doneKey);
  return true;
}
