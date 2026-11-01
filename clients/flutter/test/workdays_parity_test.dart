import 'dart:io';

import 'package:ebt_engenharia/workdays.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _d(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Checks `workdays.dart` against the data in `tests/fixtures/workdays_golden.txt`. The backend test
/// `WorkDaysParityTests` checks `WorkDays.cs` against the same file, so the two calendars cannot drift apart.
void main() {
  final lines = File('../../tests/fixtures/workdays_golden.txt').readAsLinesSync().where((l) => l.isNotEmpty && !l.startsWith('#')).toList();

  test('national holidays match the shared golden file for 2020-2040', () {
    final golden = {for (final l in lines.where((l) => l.startsWith('H '))) _d(l.substring(2))};
    expect(golden, isNotEmpty);
    final mine = {for (var y = 2020; y <= 2040; y++) ...nationalHolidays(y)};
    expect(mine, golden);
  });

  test('addWorkDays and workDaysBetween match the shared golden file', () {
    for (final l in lines) {
      final p = l.split(' ');
      switch (p[0]) {
        case 'A':
          expect(addWorkDays(_d(p[1]), int.parse(p[2])), _d(p[3]), reason: l);
        case 'B':
          expect(workDaysBetween(_d(p[1]), _d(p[2])), int.parse(p[3]), reason: l);
      }
    }
  });
}
