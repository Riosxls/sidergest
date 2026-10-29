import 'package:ebt_engenharia/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('ETag is remembered from GET, sent on PUT, and 412 is mapped', () async {
    final seen = <http.Request>[];
    final client = MockClient((r) async {
      seen.add(r);
      if (r.method == 'GET') return http.Response('{"id":5}', 200, headers: {'etag': '"42"'});
      if (r.headers['If-Match'] == '"42"') {
        return http.Response('{"title":"Stale version","status":412}', 412);
      }
      return http.Response('{}', 200);
    });
    final api = ApiClient(baseUrl: 'http://x', client: client);

    await api.put('/api/sales/quotes/9', {});
    expect(seen.last.headers.containsKey('If-Match'), isFalse);

    await api.get('/api/sales/quotes/5');
    await expectLater(
      api.put('/api/sales/quotes/5/send', {}),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 412).having((e) => e.message, 'message', contains('alterado por outra pessoa'))),
    );
    expect(seen.last.headers['If-Match'], '"42"');

    api.clearVersions();
    await api.put('/api/sales/quotes/5', {});
    expect(seen.last.headers.containsKey('If-Match'), isFalse);
  });
}
