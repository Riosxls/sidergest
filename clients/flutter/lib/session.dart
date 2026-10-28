import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'widgets/alerts.dart';

const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080');

class Session extends ChangeNotifier {
  Session({ApiClient? api}) : api = api ?? ApiClient(baseUrl: defaultApiUrl) {
    this.api.onUnauthorized = logout;
  }

  final ApiClient api;
  String? username;
  String? role;
  DateTime? expiresAt;
  ThemeMode themeMode = ThemeMode.system;
  final alerts = AlertCenter();

  bool get loggedIn => api.token != null && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));
  bool hasRole(Iterable<String> roles) => roles.contains(role);
  bool get canWrite => hasRole(const ['Admin', 'Engineering']);
  bool get isAdmin => role == 'Admin';
  bool get canStock => hasRole(const ['Admin', 'Stock']);
  bool get canRequest => hasRole(const ['Admin', 'Engineering', 'Stock', 'Purchasing']);
  bool get canBuy => hasRole(const ['Admin', 'Purchasing']);
  bool get canReceive => hasRole(const ['Admin', 'Purchasing', 'Stock']);
  bool get canProduce => hasRole(const ['Admin', 'Production']);
  bool get canMoveProduction => hasRole(const ['Admin', 'Production', 'Stock']);
  bool get canCustomers => hasRole(const ['Admin', 'Engineering', 'Sales', 'SalesManager']);
  bool get canSell => hasRole(const ['Admin', 'Sales', 'SalesManager']);
  bool get canApproveSales => hasRole(const ['Admin', 'SalesManager']);
  bool get canReleaseSales => hasRole(const ['Admin', 'Sales', 'SalesManager', 'Production']);
  bool get canShip => hasRole(const ['Admin', 'Sales', 'SalesManager', 'Stock']);
  String get baseUrl => api.baseUrl;

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    api.baseUrl = p.getString('apiUrl') ?? defaultApiUrl;
    themeMode = ThemeMode.values.asNameMap()[p.getString('themeMode')] ?? ThemeMode.system;
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

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('themeMode', mode.name);
    } catch (_) {}
  }

  Future<void> logout() async {
    api.token = null;
    username = null;
    role = null;
    expiresAt = null;
    alerts.value = const [];
    final p = await SharedPreferences.getInstance();
    for (final k in ['token', 'username', 'role', 'expiresAt']) {
      await p.remove(k);
    }
    notifyListeners();
  }
}
