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

  static Future<void> mark(String? doc) async {
    if (doc == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? <String>[];
      if (!list.contains(doc)) await prefs.setStringList(_key, [...list.length > 500 ? list.sublist(list.length - 500) : list, doc]);
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
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Text(message)),
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(key: const ValueKey('gate-back'), onPressed: () => Navigator.pop(c), child: const Text('Voltar')),
        TextButton(key: const ValueKey('gate-skip'), onPressed: () => Navigator.pop(c, 'skip'), child: Text(continueLabel)),
        if (onDownload != null) OutlinedButton.icon(key: const ValueKey('gate-download'), onPressed: () => Navigator.pop(c, 'download'), icon: const Icon(Icons.download_outlined), label: const Text('Baixar')),
        FilledButton.icon(key: const ValueKey('gate-print'), onPressed: () => Navigator.pop(c, 'print'), icon: const Icon(Icons.print_outlined), label: const Text('Imprimir')),
      ],
    ),
  );
  if (choice == null) return false;
  if (choice == 'print') {
    await onPrint();
  } else if (choice == 'download') {
    await onDownload!();
  }
  await PrintLog.mark(doneKey);
  return true;
}
