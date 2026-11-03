import 'package:ebt_engenharia/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseDecimal reads dots as thousands separators when three digits follow', () {
    expect(parseDecimal('1.500'), 1500);
    expect(parseDecimal('12.345.678'), 12345678);
    expect(parseDecimal('1.234,56'), 1234.56);
    expect(parseDecimal('1,5'), 1.5);
    expect(parseDecimal('1,234.56'), 1234.56);
  });

  test('parseDecimal keeps plain decimals and rejects garbage', () {
    expect(parseDecimal('12.5'), 12.5);
    expect(parseDecimal('0.500'), 0.5);
    expect(parseDecimal('1500'), 1500);
    expect(parseDecimal(' 7 '), 7);
    expect(parseDecimal('-1.500'), -1500);
    expect(parseDecimal('abc'), isNull);
    expect(parseDecimal(''), isNull);
  });
}
