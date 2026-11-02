import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('known English API messages are shown in Portuguese, unknown text is left alone', () {
    expect(translateServerText('Required'), 'Obrigatório');
    expect(translateServerText('At least 10 characters'), 'Pelo menos 10 caracteres');
    expect(translateServerText('At most 120 characters'), 'No máximo 120 caracteres');
    expect(translateServerText('8 digits'), '8 dígitos');
    expect(translateServerText('Must be greater than the last issued number (2580)'), 'Deve ser maior que o último número emitido (2580)');
    expect(translateServerText('Já está em português'), 'Já está em português');
  });

  test('field errors and problem details reach the user translated', () async {
    final client = MockClient((r) async {
      if (r.url.path == '/api/a') {
        return http.Response(jsonEncode({'errors': {'newPassword': ['At least 10 characters'], 'email': ['Invalid email']}}), 400, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'title': 'Conflict', 'detail': 'At least one active Admin must remain'}), 409, headers: {'content-type': 'application/json'});
    });
    final api = ApiClient(baseUrl: 'http://x', client: client, token: 't');
    final fields = await api.post('/api/a', {}).then<Object>((_) => 'ok', onError: (Object e) => e);
    expect(friendlyError(fields), 'Nova senha: Pelo menos 10 caracteres\nE-mail: E-mail inválido');
    final detail = await api.post('/api/b', {}).then<Object>((_) => 'ok', onError: (Object e) => e);
    expect(friendlyError(detail), contains('Deve restar pelo menos um administrador ativo'));
  });
}
