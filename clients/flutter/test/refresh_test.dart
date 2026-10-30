import 'dart:convert';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _session(String token, String refresh) => {
  'token': token,
  'username': 'ana',
  'role': 'Reader',
  'permissions': ['read'],
  'expiresAt': DateTime.now().add(const Duration(minutes: 60)).toUtc().toIso8601String(),
  'refreshToken': refresh,
  'refreshExpiresAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
};

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('401 triggers a refresh and the request is retried with the new token', () async {
    final seen = <http.Request>[];
    final client = MockClient((r) async {
      seen.add(r);
      if (r.url.path == '/api/auth/refresh') {
        expect(jsonDecode(r.body)['refreshToken'], 'rt-1');
        return http.Response(jsonEncode(_session('new', 'rt-2')), 200);
      }
      return r.headers['Authorization'] == 'Bearer new' ? http.Response('{"ok":true}', 200) : http.Response('', 401);
    });
    var unauthorized = 0;
    final api = ApiClient(baseUrl: 'http://x', client: client, token: 'old', onUnauthorized: () => unauthorized++)..refreshToken = 'rt-1';
    final got = <String>[];
    api.onRefreshed = (j) => got.add(j['token'] as String);

    final r = await api.get('/api/things');
    expect(r, {'ok': true});
    expect(api.token, 'new');
    expect(api.refreshToken, 'rt-2');
    expect(got, ['new']);
    expect(unauthorized, 0);
    expect(seen.map((e) => e.url.path), ['/api/things', '/api/auth/refresh', '/api/things']);
  });

  test('/api/auth/me refreshes silently, but a 401 from login or refresh itself never loops', () async {
    final seen = <String>[];
    final client = MockClient((r) async {
      seen.add(r.url.path);
      if (r.url.path == '/api/auth/refresh') return http.Response(jsonEncode(_session('new', 'rt-2')), 200);
      if (r.url.path == '/api/auth/login') return http.Response('', 401);
      return r.headers['Authorization'] == 'Bearer new' ? http.Response('{"username":"ana"}', 200) : http.Response('', 401);
    });
    final api = ApiClient(baseUrl: 'http://x', client: client, token: 'old')..refreshToken = 'rt-1';
    expect(await api.get('/api/auth/me'), {'username': 'ana'});
    expect(seen, ['/api/auth/me', '/api/auth/refresh', '/api/auth/me']);

    seen.clear();
    await expectLater(api.post('/api/auth/login', {'username': 'a', 'password': 'b'}), throwsA(isA<ApiException>()));
    expect(seen, ['/api/auth/login']);
  });

  test('concurrent 401s share a single refresh', () async {
    var refreshes = 0;
    final client = MockClient((r) async {
      if (r.url.path == '/api/auth/refresh') {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(jsonEncode(_session('new', 'rt-2')), 200);
      }
      return r.headers['Authorization'] == 'Bearer new' ? http.Response('{}', 200) : http.Response('', 401);
    });
    final api = ApiClient(baseUrl: 'http://x', client: client, token: 'old')..refreshToken = 'rt-1';
    await Future.wait([api.get('/api/a'), api.get('/api/b'), api.get('/api/c')]);
    expect(refreshes, 1);
  });

  test('refresh failure calls onUnauthorized', () async {
    final client = MockClient((r) async => http.Response('', 401));
    var unauthorized = 0;
    final api = ApiClient(baseUrl: 'http://x', client: client, token: 'old', onUnauthorized: () => unauthorized++)..refreshToken = 'rt-1';
    await expectLater(api.get('/api/a'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    expect(unauthorized, 1);
  });

  test('logout posts the refresh token and clears the session', () async {
    final seen = <http.Request>[];
    final client = MockClient((r) async {
      seen.add(r);
      if (r.url.path == '/api/auth/login') return http.Response(jsonEncode(_session('t', 'rt-1')), 200);
      return http.Response('', 204);
    });
    final s = Session(api: ApiClient(baseUrl: 'http://x', client: client));
    await s.login('http://x', 'ana', 'pw');
    expect(s.loggedIn, isTrue);
    await s.logout();
    await Future<void>.delayed(Duration.zero);
    final out = seen.last;
    expect(out.url.path, '/api/auth/logout');
    expect(jsonDecode(out.body)['refreshToken'], 'rt-1');
    expect(s.loggedIn, isFalse);
    expect(s.api.refreshToken, isNull);
  });

  test('restore refreshes an expired access token while the refresh token is valid', () async {
    FlutterSecureStorage.setMockInitialValues({
      'token': 'old',
      'username': 'ana',
      'role': 'Reader',
      'permissions': '["read"]',
      'expiresAt': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      'refreshToken': 'rt-1',
      'refreshExpiresAt': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
    });
    final client = MockClient((r) async => http.Response(jsonEncode(_session('fresh', 'rt-2')), 200));
    final s = Session(api: ApiClient(baseUrl: 'http://x', client: client));
    await s.restore();
    expect(s.loggedIn, isTrue);
    expect(s.api.token, 'fresh');
    expect(s.api.refreshToken, 'rt-2');
  });
}
