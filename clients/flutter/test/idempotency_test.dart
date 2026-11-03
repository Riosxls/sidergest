import 'dart:convert';
import 'dart:typed_data';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/widgets/entity_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  test('every write carries an Idempotency-Key (UUID v4), a different one per call; reads carry none', () async {
    final seen = <http.BaseRequest>[];
    final client = MockClient((r) async {
      seen.add(r);
      return http.Response('{}', 200);
    });
    final api = ApiClient(baseUrl: 'http://x', client: client);
    await api.post('/api/a', {});
    await api.post('/api/a', {});
    await api.put('/api/a/1', {});
    await api.delete('/api/a/1');
    await api.get('/api/a');
    final keys = seen.take(4).map((r) => r.headers['Idempotency-Key']).toList();
    expect(keys.every((k) => k != null && uuid.hasMatch(k)), isTrue);
    expect(keys.toSet().length, 4);
    expect(seen.last.headers.containsKey('Idempotency-Key'), isFalse);
  });

  test('an explicit key is sent as given, also on the retry after a silent token refresh', () async {
    final seen = <String?>[];
    final client = MockClient((r) async {
      if (r.url.path == '/api/auth/refresh') {
        return http.Response('{"token":"new","refreshToken":"rt2","expiresAt":"2999-01-01T00:00:00Z"}', 200);
      }
      seen.add(r.headers['Idempotency-Key']);
      return seen.length == 1 ? http.Response('', 401) : http.Response('{}', 200);
    });
    final api = ApiClient(baseUrl: 'http://x', client: client, token: 'old')..refreshToken = 'rt1';
    await api.post('/api/a', {}, idempotencyKey: 'k-1');
    expect(seen, ['k-1', 'k-1']);
  });

  test('upload sends the key too', () async {
    String? key;
    final client = MockClient((r) async {
      key = r.headers['Idempotency-Key'];
      return http.Response('{}', 200);
    });
    await ApiClient(baseUrl: 'http://x', client: client).upload('/api/a', 'file', 'a.txt', Uint8List.fromList([1, 2]), idempotencyKey: 'up-1');
    expect(key, 'up-1');
  });

  test('inside a scope the n-th write gets <base>-<n>; a repeated submit repeats the same keys', () async {
    final seen = <String?>[];
    final client = MockClient((r) async {
      seen.add(r.headers['Idempotency-Key']);
      return http.Response('{}', 200);
    });
    final api = ApiClient(baseUrl: 'http://x', client: client);
    Future<void> submit() => IdempotencyScope.run('base', () async {
      await api.post('/api/a', {});
      await Future<void>.delayed(Duration.zero);
      await api.put('/api/a/1', {});
    });
    await submit();
    await submit();
    expect(seen, ['base-1', 'base-2', 'base-1', 'base-2']);
    await api.post('/api/a', {});
    expect(seen.last, isNot(startsWith('base')));
  });

  test('409 "em andamento" reads like a timeout: unknown outcome, wait and check', () async {
    final client = MockClient((r) async => http.Response.bytes(utf8.encode('{"title":"Request in progress","detail":"A ação anterior ainda está em andamento"}'), 409));
    final api = ApiClient(baseUrl: 'http://x', client: client);
    await expectLater(
      api.post('/api/a', {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.inProgress, 'inProgress', isTrue)
            .having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)
            .having((e) => e.message, 'message', 'A ação anterior ainda está em andamento. Aguarde um instante e confira antes de repetir.'),
      ),
    );
  });

  test('another 409 keeps its own message and is a definite answer', () async {
    final client = MockClient((r) async => http.Response.bytes(utf8.encode('{"message":"Há recebimento em andamento"}'), 409));
    final api = ApiClient(baseUrl: 'http://x', client: client);
    await expectLater(api.post('/api/a', {}), throwsA(isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', isFalse).having((e) => e.message, 'm', contains('recebimento'))));
  });

  test('the If-Match cache is bounded and drops the least recently used entry', () {
    final m = LruMap<String, int>(3);
    m['a'] = 1;
    m['b'] = 2;
    m['c'] = 3;
    expect(m['a'], 1); // touch a: b is now the oldest
    m['d'] = 4;
    expect(m.length, 3);
    expect(m['b'], isNull);
    expect(m['a'], 1);
    expect(m['d'], 4);
  });

  test('ApiClient forgets old versions beyond its bound', () async {
    final puts = <String?>[];
    final client = MockClient((r) async {
      if (r.method == 'GET') return http.Response('{}', 200, headers: {'etag': '"${r.url.path}"'});
      puts.add(r.headers['If-Match']);
      return http.Response('{}', 200);
    });
    final api = ApiClient(baseUrl: 'http://x', client: client);
    for (var i = 1; i <= 310; i++) {
      await api.get('/api/items/$i');
    }
    await api.put('/api/items/1', {});
    await api.put('/api/items/310', {});
    expect(puts, [null, '"/api/items/310"']);
  });

  group('form', () {
    Future<void> open(WidgetTester tester, Future<Map<String, dynamic>?> Function(Map<String, dynamic>) onSubmit) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntityFormDialog(api: ApiClient(baseUrl: 'http://x'), title: 'Teste', fields: const [FieldSpec('name', 'Nome')], onSubmit: onSubmit),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a retry of the same content after a lost answer reuses the key; editing or a refusal starts a new one', (tester) async {
      final keys = <String?>[];
      var attempt = 0;
      await open(tester, (b) async {
        keys.add(IdempotencyScope.nextInScope());
        attempt++;
        if (attempt == 1) throw ApiException(0, 'Conexão perdida');
        return b;
      });
      await tester.enterText(find.byKey(const ValueKey('field-name')), 'Ana');
      Future<void> save() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
        await tester.pumpAndSettle();
      }

      await save(); // 1: connection lost
      await save(); // 2: same content -> same key; this one would succeed, so the form is gone
      expect(keys[0], isNotNull);
      expect(keys[1], keys[0]);
    });

    testWidgets('after the user edits the content the next attempt uses a new key', (tester) async {
      final keys = <String?>[];
      var attempt = 0;
      await open(tester, (b) async {
        keys.add(IdempotencyScope.nextInScope());
        if (++attempt <= 2) throw ApiException(0, 'Conexão perdida');
        return b;
      });
      Future<void> save() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byKey(const ValueKey('field-name')), 'Ana');
      await save();
      await tester.enterText(find.byKey(const ValueKey('field-name')), 'Ana Maria');
      await save();
      expect(keys[1], isNot(keys[0]));
    });

    testWidgets('a definite refusal drops the key', (tester) async {
      final keys = <String?>[];
      var attempt = 0;
      await open(tester, (b) async {
        keys.add(IdempotencyScope.nextInScope());
        if (++attempt == 1) throw ApiException(422, 'Recusado');
        return b;
      });
      Future<void> save() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byKey(const ValueKey('field-name')), 'Ana');
      await save();
      await save();
      expect(keys[1], isNot(keys[0]));
    });
  });
}
