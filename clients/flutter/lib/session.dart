import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'widgets/alerts.dart';

const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080');

class Session extends ChangeNotifier {
  Session({ApiClient? api, FlutterSecureStorage? storage})
    : api = api ?? ApiClient(baseUrl: defaultApiUrl),
      _storage = storage ?? const FlutterSecureStorage() {
    this.api.onUnauthorized = logout;
  }

  final ApiClient api;
  final FlutterSecureStorage _storage;
  static const _secureKeys = ['token', 'username', 'role', 'expiresAt', 'permissions'];
  String? username;
  String? role;
  Set<String> permissions = const {};
  DateTime? expiresAt;
  ThemeMode themeMode = ThemeMode.system;
  final alerts = AlertCenter();

  bool get loggedIn => api.token != null && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));
  bool get canWrite => permissions.contains('write');
  bool get isAdmin => permissions.contains('admin');
  bool get canStock => permissions.contains('stock');
  bool get canRequest => permissions.contains('purchasing-request');
  bool get canBuy => permissions.contains('purchasing');
  bool get canReceive => permissions.contains('receiving');
  bool get canProduce => permissions.contains('production');
  bool get canMoveProduction => permissions.contains('production-materials');
  bool get canSell => permissions.contains('sales');
  bool get canApproveSales => permissions.contains('sales-approve');
  bool get canReleaseSales => permissions.contains('sales-release');
  bool get canShip => permissions.contains('sales-ship');
  String get baseUrl => api.baseUrl;

  Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      api.baseUrl = p.getString('apiUrl') ?? defaultApiUrl;
      themeMode = ThemeMode.values.asNameMap()[p.getString('themeMode')] ?? ThemeMode.system;
    } catch (_) {}
    try {
      final v = await _storage.readAll();
      final exp = DateTime.tryParse(v['expiresAt'] ?? '');
      if (exp != null && exp.isAfter(DateTime.now()) && v['token'] != null) {
        api.token = v['token'];
        username = v['username'];
        role = v['role'];
        permissions = (jsonDecode(v['permissions'] ?? '[]') as List).cast<String>().toSet();
        expiresAt = exp;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> login(String url, String user, String password) async {
    api.baseUrl = url.trim();
    api.token = null;
    final r = await api.post('/api/auth/login', {'username': user, 'password': password}) as Map<String, dynamic>;
    api.token = r['token'] as String;
    username = r['username'] as String;
    role = r['role'] as String;
    permissions = ((r['permissions'] as List?) ?? const []).cast<String>().toSet();
    expiresAt = DateTime.parse(r['expiresAt'] as String);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('apiUrl', api.baseUrl);
    } catch (_) {}
    try {
      await _storage.write(key: 'token', value: api.token);
      await _storage.write(key: 'username', value: username);
      await _storage.write(key: 'role', value: role);
      await _storage.write(key: 'expiresAt', value: expiresAt!.toIso8601String());
      await _storage.write(key: 'permissions', value: jsonEncode(permissions.toList()));
    } catch (_) {}
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
    api.clearVersions();
    username = null;
    role = null;
    permissions = const {};
    expiresAt = null;
    alerts.value = const [];
    for (final k in _secureKeys) {
      try {
        await _storage.delete(key: k);
      } catch (_) {}
    }
    notifyListeners();
  }
}
