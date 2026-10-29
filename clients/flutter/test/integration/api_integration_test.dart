// Talks to a REAL API (no mocks). Skipped unless EBT_API_URL and EBT_ADMIN_PASSWORD are set, e.g.:
//   EBT_API_URL=http://localhost:8080 EBT_ADMIN_PASSWORD=... flutter test test/integration
import 'dart:io';

import 'package:ebt_engenharia/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['EBT_API_URL'];
  final password = Platform.environment['EBT_ADMIN_PASSWORD'];
  final user = Platform.environment['EBT_ADMIN_USER'] ?? 'admin';
  final skip = (url == null || password == null) ? 'set EBT_API_URL and EBT_ADMIN_PASSWORD to run' : null;

  late ApiClient api;

  Future<Map<String, dynamic>> login(ApiClient c) async {
    final r = await c.post('/api/auth/login', {'username': user, 'password': password}) as Map<String, dynamic>;
    c.token = r['token'] as String;
    c.refreshToken = r['refreshToken'] as String?;
    return r;
  }

  setUp(() async {
    api = ApiClient(baseUrl: url ?? 'http://localhost:8080');
    await login(api);
  });

  test('login returns permissions and a refresh token', () async {
    final r = await login(ApiClient(baseUrl: url!));
    expect(r['permissions'], containsAll(['read', 'admin', 'sales']));
    expect(r['refreshToken'], isNotEmpty);
    final me = await api.get('/api/auth/me') as Map<String, dynamic>;
    expect(me['permissions'], contains('admin'));
  }, skip: skip);

  test('wrong password is rejected', () async {
    final c = ApiClient(baseUrl: url!);
    expect(() => c.post('/api/auth/login', {'username': user, 'password': 'definitely-wrong-password'}), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
  }, skip: skip);

  test('an expired access token is refreshed transparently and the refresh token rotates', () async {
    final before = api.refreshToken;
    var refreshed = 0;
    api.onRefreshed = (_) => refreshed++;
    api.token = 'not-a-valid-token';
    expect(await api.get('/api/products', {'take': 1}), isA<Map>());
    expect(refreshed, 1);
    expect(api.refreshToken, isNot(before));

    // the old refresh token is single-use
    final replay = ApiClient(baseUrl: url!)..refreshToken = before;
    expect(await replay.refresh(), isFalse);
  }, skip: skip);

  test('stale If-Match on a customer edit gives 412 and the fresh tag works', () async {
    final name = 'Integracao ${DateTime.now().microsecondsSinceEpoch}';
    final created = await api.post('/api/customers', {'name': name, 'consumerType': 'Normal', 'active': true}) as Map<String, dynamic>;
    final path = '/api/customers/${created['id']}';
    await api.get(path); // remembers the ETag

    final other = ApiClient(baseUrl: url!);
    await login(other);
    await other.get(path);
    await other.put(path, {'name': '$name editado', 'consumerType': 'Normal', 'active': true}); // someone else saves first

    await expectLater(
      api.put(path, {'name': '$name meu', 'consumerType': 'Normal', 'active': true}),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 412)),
    );
    await api.get(path); // reload picks up the new tag
    final saved = await api.put(path, {'name': '$name meu', 'consumerType': 'Normal', 'active': true}) as Map<String, dynamic>;
    expect(saved['name'], '$name meu');
  }, skip: skip);

  test('audit log records the customer change', () async {
    final name = 'Auditoria ${DateTime.now().microsecondsSinceEpoch}';
    final created = await api.post('/api/customers', {'name': name, 'consumerType': 'Normal', 'active': true}) as Map<String, dynamic>;
    final page = await api.get('/api/audit', {'entity': 'Customer', 'entityId': '${created['id']}'}) as Map<String, dynamic>;
    expect((page['items'] as List).map((e) => e['action']), contains('Insert'));
  }, skip: skip);
}
