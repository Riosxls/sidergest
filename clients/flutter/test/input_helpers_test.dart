import 'package:ebt_engenharia/screens/customers.dart' show phoneHint;
import 'package:ebt_engenharia/widgets/date_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String _type(String keys) {
  const f = DateSlashFormatter();
  var v = TextEditingValue.empty;
  for (final ch in keys.split('')) {
    final next = TextEditingValue(text: v.text + ch, selection: TextSelection.collapsed(offset: v.text.length + 1));
    v = f.formatEditUpdate(v, next);
  }
  return v.text;
}

void main() {
  group('DateSlashFormatter', () {
    test('types the slashes after day and month', () => expect(_type('04112026'), '04/11/2026'));
    test('keeps slashes typed by hand and the shorthand', () {
      expect(_type('5/3/26'), '5/3/26');
      expect(_type('04/11/2026'), '04/11/2026');
    });
    test('drops a doubled slash and a leading one', () {
      expect(_type('04//11'), '04/11/');
      expect(_type('/'), '');
    });
    test('stops at four digits of year and leaves deleting alone', () {
      expect(_type('041120261'), '04/11/2026');
      const f = DateSlashFormatter();
      const old = TextEditingValue(text: '04/');
      const shorter = TextEditingValue(text: '04');
      expect(f.formatEditUpdate(old, shorter).text, '04');
    });
    test('leaves ISO dates and pastes as they are', () {
      const f = DateSlashFormatter();
      const pasted = TextEditingValue(text: '2026-11-04');
      expect(f.formatEditUpdate(TextEditingValue.empty, pasted).text, '2026-11-04');
    });
  });

  group('phoneHint', () {
    test('is silent for empty, 8 to 11 digits and other fields', () {
      expect(phoneHint('phone', {'phone': ''}), isNull);
      expect(phoneHint('phone', {}), isNull);
      expect(phoneHint('phone', {'phone': '(11) 3456-7890'}), isNull);
      expect(phoneHint('company.phone', {'company.phone': '11 98765-4321'}), isNull);
      expect(phoneHint('email', {'email': '1'}), isNull);
    });
    test('warns, never blocks, outside 8 to 11 digits', () {
      expect(phoneHint('phone', {'phone': '3456'}), contains('8 a 11'));
      expect(phoneHint('phone', {'phone': '551134567890123'}), contains('mais de 11'));
    });
  });
}
