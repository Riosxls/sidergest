import 'package:ebt_engenharia/screens/sales_quotes.dart';
import 'package:ebt_engenharia/workdays.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weekends and national holidays are skipped', () {
    // Friday 30 Oct 2026 + 1: Saturday, Sunday and Monday 2 Nov (Finados) are skipped.
    expect(addWorkDays(DateTime(2026, 10, 30), 1), DateTime(2026, 11, 3));
    expect(addWorkDays(DateTime(2026, 11, 3), 4), DateTime(2026, 11, 9));
    expect(addWorkDays(DateTime(2026, 10, 24), 0), DateTime(2026, 10, 24));
    expect(addWorkDays(DateTime(2026, 10, 24), 1), DateTime(2026, 10, 26));
  });

  test('Good Friday, fixed holidays and the 2024 Consciência Negra rule', () {
    expect(isWorkDay(DateTime(2026, 4, 3)), isFalse);
    expect(isWorkDay(DateTime(2026, 9, 7)), isFalse);
    expect(isWorkDay(DateTime(2026, 11, 20)), isFalse);
    expect(isWorkDay(DateTime(2023, 11, 20)), isTrue);
    expect(addWorkDays(DateTime(2026, 4, 2), 1), DateTime(2026, 4, 6));
  });

  test('workDaysBetween is the inverse of addWorkDays', () {
    final start = DateTime(2026, 10, 30);
    for (var n = 0; n <= 40; n++) {
      expect(workDaysBetween(start, addWorkDays(start, n)), n);
    }
    expect(workDaysBetween(start, DateTime(2026, 10, 27)), 0);
  });

  test('item dialog has no IPI or ICMS fields; taxes come from the price table', () {
    final keys = salesLineFields.map((f) => f.key);
    expect(keys, isNot(contains('ipiPercent')));
    expect(keys, isNot(contains('icmsPercent')));
    expect(salesLineFields.firstWhere((f) => f.key == 'leadTimeDays').label, contains('dias úteis'));
  });
}
