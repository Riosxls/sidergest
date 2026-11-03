import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Shared PDF fonts and theme for every document builder. The Roboto files are read and parsed once per app run, not once per PDF.
///
/// [italicAsRegular] maps italic text to the regular face (Roboto italic is not bundled): used by the NF and DANFE papers.
Future<pw.ThemeData> pdfTheme({bool italicAsRegular = false}) async {
  // The parsed fonts are remembered, not the Future that produced them: a finished Future from another zone (a previous widget test) would never call back.
  final f = _loaded ?? await _loadFonts();
  return pw.ThemeData.withFont(base: f.regular, bold: f.bold, italic: italicAsRegular ? f.regular : null);
}

typedef _Fonts = ({pw.Font regular, pw.Font bold});

_Fonts? _loaded;
Future<_Fonts>? _loading;

Future<_Fonts> _loadFonts() => _loading ??= () async {
  try {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
    return _loaded = (regular: regular, bold: bold);
  } finally {
    // Success is remembered in [_loaded]; after a failure the next document tries again.
    _loading = null;
  }
}();

/// Final step of every builder: serializes the document. Kept in one place so the work can move off the UI thread without touching the builders.
///
/// A [pw.Document] holds page-building closures and font objects, which cannot be sent to another isolate; moving the layout there means building
/// the whole document inside the isolate from plain data and font bytes. Until the builders take that shape, this runs on the calling isolate.
Future<Uint8List> savePdf(pw.Document doc) => doc.save();
