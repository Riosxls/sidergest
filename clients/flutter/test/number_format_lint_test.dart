import 'dart:io';

import 'package:ebt_engenharia/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pt-BR numbers go through the helpers of entities.dart, not hand-rolled toStringAsFixed().replaceAll', () {
    final bad = <String>[];
    final pattern = RegExp(r"toStringAsFixed\([^)]*\)\s*\.replaceAll\('\.',\s*','\)");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.replaceAll('\\', '/').endsWith('lib/entities.dart')) continue;
      if (pattern.hasMatch(f.readAsStringSync())) bad.add(f.path);
    }
    expect(bad, isEmpty, reason: 'use fmtNum / fmtMoney / fmtDecimalInput from entities.dart');
  });

  test('fmtDecimalInput and fmtDayOf', () {
    expect(fmtDecimalInput(1234.5), '1234,50');
    expect(fmtDecimalInput(2, 0), '2');
    expect(fmtDayOf(DateTime(2026, 3, 7)), '07/03/2026');
  });
}
