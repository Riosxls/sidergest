import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:5241');

class Session extends ChangeNotifier {
  Session({ApiClient? api}) : api = api ?? ApiClient(baseUrl: defaultApiUrl) {
    this.api.onUnauthorized = logout;
  }

  final ApiClient api;
  String? username;
  String? role;
  DateTime? expiresAt;

  bool get loggedIn => api.token != null && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));
  bool get canWrite => role == 'Admin' || role == 'Engineering';
  String get baseUrl => api.baseUrl;

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    api.baseUrl = p.getString('apiUrl') ?? defaultApiUrl;
    final exp = DateTime.tryParse(p.getString('expiresAt') ?? '');
    if (exp != null && exp.isAfter(DateTime.now())) {
      api.token = p.getString('token');
      username = p.getString('username');
      role = p.getString('role');
      expiresAt = exp;
    }
    notifyListeners();
  }

  Future<void> login(String url, String user, String password) async {
    api.baseUrl = url.trim();
    api.token = null;
    final r = await api.post('/api/auth/login', {'username': user, 'password': password}) as Map<String, dynamic>;
    api.token = r['token'] as String;
    username = r['username'] as String;
    role = r['role'] as String;
    expiresAt = DateTime.parse(r['expiresAt'] as String);
    final p = await SharedPreferences.getInstance();
    await p.setString('apiUrl', api.baseUrl);
    await p.setString('token', api.token!);
    await p.setString('username', username!);
    await p.setString('role', role!);
    await p.setString('expiresAt', expiresAt!.toIso8601String());
    notifyListeners();
  }

  Future<void> logout() async {
    api.token = null;
    username = null;
    role = null;
    expiresAt = null;
    final p = await SharedPreferences.getInstance();
    for (final k in ['token', 'username', 'role', 'expiresAt']) {
      await p.remove(k);
    }
    notifyListeners();
  }
}
