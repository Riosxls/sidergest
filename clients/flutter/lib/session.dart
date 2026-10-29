import 'dart:async';
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
    this.api.onRefreshed = (r) => unawaited(_apply(r));
  }

  final ApiClient api;
  final FlutterSecureStorage _storage;
  static const _secureKeys = ['token', 'username', 'role', 'expiresAt', 'permissions', 'refreshToken', 'refreshExpiresAt'];
  String? username;
  String? role;
  Set<String> permissions = const {};
  DateTime? expiresAt;
  DateTime? refreshExpiresAt;
  ThemeMode themeMode = ThemeMode.system;
  final alerts = AlertCenter();

  bool get loggedIn => api.token != null && ((expiresAt?.isAfter(DateTime.now()) ?? true) || _refreshValid);
  bool get canWrite => permissions.contains('write');
  bool get isAdmin => permissions.contains('admin');
  bool get canStock => permissions.contains('stock');
  bool get canRequest => permissions.contains('purchasing-request');
  bool get canBuy => permissions.contains('purchasing');
  bool get canReceive => permissions.contains('receiving');
  bool get canProduce => permissions.contains('production');
  bool get canMoveProduction => permissions.contains('production-materials');
  bool get canCustomers => permissions.contains('customers');
  bool get canSell => permissions.contains('sales');
  bool get canApproveSales => permissions.contains('sales-approve');
  bool get canReleaseSales => permissions.contains('sales-release');
  bool get canShip => permissions.contains('sales-ship');
  bool get canCertificate => permissions.contains('certificates');
  bool get canSignQuality => permissions.contains('viability-quality');
  bool get canSignProduction => permissions.contains('viability-production');
  bool get canSignCommercial => permissions.contains('viability-commercial');
  bool get canSteel => permissions.contains('steel');
  bool get canFiscalPrices => permissions.contains('fiscal-prices');
  bool get canFiscalCancel => permissions.contains('fiscal-cancel');
  String get baseUrl => api.baseUrl;

  bool get _refreshValid => api.refreshToken != null && refreshExpiresAt != null && refreshExpiresAt!.isAfter(DateTime.now());

  Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      api.baseUrl = p.getString('apiUrl') ?? defaultApiUrl;
      themeMode = ThemeMode.values.asNameMap()[p.getString('themeMode')] ?? ThemeMode.system;
    } catch (_) {}
    try {
      final v = await _storage.readAll();
      final exp = DateTime.tryParse(v['expiresAt'] ?? '');
      final rExp = DateTime.tryParse(v['refreshExpiresAt'] ?? '');
      final rt = v['refreshToken'];
      final accessValid = exp != null && exp.isAfter(DateTime.now());
      final refreshValid = rt != null && rExp != null && rExp.isAfter(DateTime.now());
      if (v['token'] != null && (accessValid || refreshValid)) {
        api.token = v['token'];
        api.refreshToken = rt;
        username = v['username'];
        role = v['role'];
        permissions = (jsonDecode(v['permissions'] ?? '[]') as List).cast<String>().toSet();
        expiresAt = exp;
        refreshExpiresAt = rExp;
        if (!accessValid && !await api.refresh()) await logout();
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Applies a login/refresh response and persists it.
  Future<void> _apply(Map<String, dynamic> r) async {
    api.token = r['token'] as String;
    api.refreshToken = r['refreshToken'] as String?;
    username = r['username'] as String? ?? username;
    role = r['role'] as String? ?? role;
    if (r['permissions'] is List) permissions = (r['permissions'] as List).cast<String>().toSet();
    expiresAt = DateTime.parse(r['expiresAt'] as String);
    refreshExpiresAt = DateTime.tryParse('${r['refreshExpiresAt'] ?? ''}');
    try {
      await _storage.write(key: 'token', value: api.token);
      await _storage.write(key: 'username', value: username);
      await _storage.write(key: 'role', value: role);
      await _storage.write(key: 'expiresAt', value: expiresAt!.toIso8601String());
      await _storage.write(key: 'permissions', value: jsonEncode(permissions.toList()));
      if (api.refreshToken != null) {
        await _storage.write(key: 'refreshToken', value: api.refreshToken);
        await _storage.write(key: 'refreshExpiresAt', value: refreshExpiresAt?.toIso8601String());
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> login(String url, String user, String password) async {
    api.baseUrl = url.trim();
    api.token = null;
    api.refreshToken = null;
    final r = await api.post('/api/auth/login', {'username': user, 'password': password}) as Map<String, dynamic>;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('apiUrl', api.baseUrl);
    } catch (_) {}
    await _apply(r);
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
    final rt = api.refreshToken;
    if (rt != null) {
      // Best effort: revoke the refresh token server-side without blocking the UI.
      unawaited(api.post('/api/auth/logout', {'refreshToken': rt}).then<void>((_) {}, onError: (_) {}));
    }
    api.token = null;
    api.refreshToken = null;
    api.clearVersions();
    username = null;
    role = null;
    permissions = const {};
    expiresAt = null;
    refreshExpiresAt = null;
    alerts.value = const [];
    for (final k in _secureKeys) {
      try {
        await _storage.delete(key: k);
      } catch (_) {}
    }
    notifyListeners();
  }
}
