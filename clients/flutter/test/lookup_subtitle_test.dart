import 'package:ebt_engenharia/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subtitle formats CNPJ and city/UF', () {
    expect(
      LookupSpec.subtitle({
        'defaultAddress': {'document': '12345678000190', 'city': 'Campinas', 'uf': 'SP'},
      }),
      '12.345.678/0001-90 · Campinas/SP',
    );
  });

  test('subtitle formats CPF and tolerates missing parts', () {
    expect(
      LookupSpec.subtitle({
        'defaultAddress': {'document': '12345678901'},
      }),
      '123.456.789-01',
    );
    expect(LookupSpec.subtitle({'defaultAddress': {'city': 'Jundiaí'}}), 'Jundiaí');
    expect(LookupSpec.subtitle({'name': 'x'}), isNull);
    expect(LookupSpec.subtitle({'defaultAddress': <String, dynamic>{}}), isNull);
  });
}
