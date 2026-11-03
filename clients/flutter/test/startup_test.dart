import 'dart:async';

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'token': 'old',
      'username': 'ana',
      'role': 'Reader',
      'permissions': '["read","write"]',
      'expiresAt': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      'refreshToken': 'rt-1',
      'refreshExpiresAt': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
    });
  });

  test('restoreLocal never waits on the network and keeps the stored permissions', () async {
    final never = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((r) {
      calls++;
      return never.future;
    });
    final s = Session(api: ApiClient(baseUrl: 'http://x', client: client));
    await s.restoreLocal().timeout(const Duration(seconds: 2));
    expect(calls, 0);
    expect(s.loggedIn, isTrue);
    expect(s.username, 'ana');
    expect(s.canWrite, isTrue);
    // The background half starts the requests (they hang here) without having blocked the first frame.
    unawaited(s.refreshRemote());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 1);
  });

  test('the background refresh replaces stale permissions with the server answer', () async {
    final client = MockClient((r) async {
      if (r.url.path == '/api/auth/refresh') {
        return http.Response(
          '{"token":"new","refreshToken":"rt-2","username":"ana","role":"Reader","permissions":["read","write"],"expiresAt":"${DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()}"}',
          200,
        );
      }
      return http.Response('{"role":"Reader","permissions":["read"]}', 200);
    });
    final s = Session(api: ApiClient(baseUrl: 'http://x', client: client));
    await s.restoreLocal();
    expect(s.canWrite, isTrue);
    await s.refreshRemote();
    expect(s.canWrite, isFalse);
    expect(s.loggedIn, isTrue);
  });

  test('the background refresh signs out when the server refuses the session', () async {
    final client = MockClient((r) async => http.Response('', 401));
    final s = Session(api: ApiClient(baseUrl: 'http://x', client: client));
    await s.restoreLocal();
    expect(s.loggedIn, isTrue);
    await s.refreshRemote();
    expect(s.loggedIn, isFalse);
  });
}
