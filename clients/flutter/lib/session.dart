import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'prefs.dart';
import 'widgets/alerts.dart';

const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080');

/// Signed-in state (token, role, permissions) and personal preferences. Notifies listeners on change; persists to secure storage and SharedPreferences.
class Session extends ChangeNotifier {
  Session({ApiClient? api, FlutterSecureStorage? storage})
    : api = api ?? ApiClient(baseUrl: defaultApiUrl),
      _storage = storage ?? const FlutterSecureStorage() {
    this.api.onUnauthorized = logout;
    this.api.onRefreshRejected = _adoptStored;
    this.api.onRefreshed = (r) => unawaited(_apply(r).catchError((Object e) => debugPrint('session: could not apply the refreshed session: $e')));
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

  /// Interface density: compact (default) fits more rows; comfortable has larger touch targets.
  bool comfortable = false;

  /// Text size multiplier (1 = normal).
  double textScale = 1;

  /// When false the session lives in memory only: closing the app signs the user out.
  bool remember = true;

  /// Username offered on the login screen (kept only while "remember" is on).
  String lastUser = '';

  /// Screen opened after sign-in (a nav item id).
  String homeScreen = 'dashboard';

  /// Minutes between automatic Painel refreshes; 0 turns it off.
  int dashboardRefreshMinutes = 2;

  /// Rows per page in lists (see [AppPrefs.rowsPerPage]).
  int rowsPerPage = 50;

  bool reduceMotion = false;
  bool highContrast = false;

  /// Ask to print or download a paper before a step ends (see `printGate`).
  bool printPrompts = true;

  /// Sign out after this many idle minutes; 0 never. The server's effective value (it is the source of truth, per user).
  int idleLockMinutes = 0;

  /// Longest idle time the administrator allows; 0 means no cap.
  int maxIdleMinutes = 0;

  /// Set when the idle lock signed the user out, so the login screen can say why. Cleared by the next login.
  bool idleSignedOut = false;

  /// Set by "Sair" in the avatar menu (not by the idle lock or an expired session), so the Shell does not offer the place the user left to whoever signs in next.
  bool signedOutManually = false;

  /// Shown instead of the username when set (kept on the server).
  String? displayName;
  String? email;

  static const dashboardRefreshChoices = [0, 2, 5, 10];
  static const idleLockChoices = [0, 15, 30, 60];
  static const textScaleChoices = [1.0, 1.15, 1.3];

  /// Idle-lock options offered in the settings: with an administrator cap the larger ones and "Nunca" disappear, and an effective value
  /// outside the list (the cap itself, or a server default such as 45) is added so the current setting is always shown.
  List<int> get idleChoices {
    final list = [
      for (final m in idleLockChoices)
        if (maxIdleMinutes <= 0 || (m > 0 && m <= maxIdleMinutes)) m,
    ];
    if (!list.contains(idleLockMinutes)) list.add(idleLockMinutes);
    list.sort((a, b) => a == 0 ? -1 : (b == 0 ? 1 : a.compareTo(b)));
    return list;
  }

  /// Name this device gives itself on the server's list of connected devices.
  static String get deviceLabel {
    final os = switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Windows',
      TargetPlatform.android => 'Android',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
    return kIsWeb ? 'Navegador' : os;
  }

  String get shownName => (displayName?.trim().isNotEmpty ?? false) ? displayName!.trim() : (username ?? '');

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
  bool get canIssueCertificate => permissions.contains('certificates-issue');
  bool get canEmitInvoice => permissions.contains('fiscal-emit');
  bool get canPostReceivables => permissions.contains('receivables-post');
  bool get canEditPrices => permissions.contains('price-edit');
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
      remember = p.getBool('rememberLogin') ?? true;
      lastUser = p.getString('lastUser') ?? '';
      comfortable = p.getBool('comfortable') ?? false;
      textScale = snapTextScale(p.getDouble('textScale') ?? 1);
      homeScreen = p.getString('homeScreen') ?? 'dashboard';
      final refresh = p.getInt('dashboardRefreshMinutes') ?? 2;
      dashboardRefreshMinutes = dashboardRefreshChoices.contains(refresh) ? refresh : 2;
      final rows = p.getInt('rowsPerPage') ?? 50;
      rowsPerPage = AppPrefs.rowsPerPageChoices.contains(rows) ? rows : 50;
      reduceMotion = p.getBool('reduceMotion') ?? false;
      highContrast = p.getBool('highContrast') ?? false;
      printPrompts = p.getBool('printPrompts') ?? true;
      AppPrefs.rowsPerPage = rowsPerPage;
      AppPrefs.printPrompts = printPrompts;
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
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
        if (!accessValid && !await api.refresh() && api.refreshRejected) await logout();
        if (api.token != null) {
          await _syncProfile();
          await _migrateIdlePref();
          reportActivity();
        }
      }
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
    notifyListeners();
  }

  /// Re-reads role and permissions from the server so a stored session never keeps stale rights
  /// (for example one saved by an older server version, or before an admin changed the role).
  Future<void> _syncProfile() async {
    try {
      final me = await api.get('/api/auth/me') as Map<String, dynamic>;
      role = me['role'] as String? ?? role;
      if (me['permissions'] is List) permissions = (me['permissions'] as List).cast<String>().toSet();
      displayName = me['displayName'] as String?;
      email = me['email'] as String?;
      _adoptIdle(me);
      if (remember) await _storage.write(key: 'permissions', value: jsonEncode(permissions.toList()));
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  /// Takes the idle-lock values the server sent (login, /auth/me, PUT /auth/idle-lock); absent fields leave the current value.
  void _adoptIdle(Map<String, dynamic> r) {
    final v = r['idleLockMinutes'];
    if (v is num) idleLockMinutes = v.toInt();
    final m = r['maxIdleMinutes'];
    if (m is num) maxIdleMinutes = m.toInt();
  }

  /// Older versions kept the idle lock per device in local storage. When the server has none, send that value once; then drop it.
  Future<void> _migrateIdlePref() async {
    try {
      final p = await SharedPreferences.getInstance();
      final old = p.getInt('idleLockMinutes');
      if (old == null) return;
      if (idleLockMinutes == 0 && old > 0 && idleLockChoices.contains(old)) {
        await setIdleLockMinutes(old);
      }
      await p.remove('idleLockMinutes');
    } catch (e) {
      debugPrint('session: idle lock migration will retry on the next start: $e');
    }
  }

  /// Another tab of the same browser may have refreshed first: its new session is in storage while this tab still holds the rotated-out token.
  /// Takes that session over instead of signing out. False when storage holds nothing newer.
  Future<bool> _adoptStored() async {
    try {
      final v = await _storage.readAll();
      final token = v['token'];
      final rt = v['refreshToken'];
      final rExp = DateTime.tryParse(v['refreshExpiresAt'] ?? '');
      if (token == null || rt == null || rt == api.refreshToken || rExp == null || !rExp.isAfter(DateTime.now())) return false;
      api.token = token;
      api.refreshToken = rt;
      expiresAt = DateTime.tryParse(v['expiresAt'] ?? '');
      refreshExpiresAt = rExp;
      return true;
    } catch (_) {
      // Storage unreadable: nothing to adopt, the caller treats it as a refused refresh.
      return false;
    }
  }

  /// Applies a login/refresh response and persists it.
  Future<void> _apply(Map<String, dynamic> r) async {
    _adoptIdle(r);
    api.token = r['token'] as String;
    api.refreshToken = r['refreshToken'] as String?;
    username = r['username'] as String? ?? username;
    role = r['role'] as String? ?? role;
    if (r['permissions'] is List) permissions = (r['permissions'] as List).cast<String>().toSet();
    expiresAt = DateTime.parse(r['expiresAt'] as String);
    refreshExpiresAt = DateTime.tryParse('${r['refreshExpiresAt'] ?? ''}');
    if (!remember) return notifyListeners();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
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
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  /// [remember] keeps the session across app restarts and offers [user] again next time; without it nothing is stored.
  Future<void> login(String url, String user, String password, {bool remember = true}) async {
    api.baseUrl = url.trim();
    api.token = null;
    api.refreshToken = null;
    final r = await api.post('/api/auth/login', {'username': user, 'password': password, 'device': deviceLabel}) as Map<String, dynamic>;
    idleSignedOut = false;
    signedOutManually = false;
    this.remember = remember;
    lastUser = remember ? user.trim() : '';
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('apiUrl', api.baseUrl);
      await p.setBool('rememberLogin', remember);
      if (remember) {
        await p.setString('lastUser', lastUser);
      } else {
        await p.remove('lastUser');
      }
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
    await _apply(r);
    await _migrateIdlePref();
    reportActivity(force: true);
  }

  /// Turns "stay signed in on this device" on or off for the running session; off removes the stored tokens now.
  Future<void> setRemember(bool value) async {
    remember = value;
    lastUser = value ? (username ?? '') : '';
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('rememberLogin', value);
      if (value) {
        await p.setString('lastUser', lastUser);
      } else {
        await p.remove('lastUser');
      }
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
    if (value) {
      await _persist();
    } else {
      for (final k in _secureKeys) {
        try {
          await _storage.delete(key: k);
        } catch (e) {
          debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
          // Local storage is best effort; the in-memory value stays.
        }
      }
    }
    notifyListeners();
  }

  Future<void> setComfortable(bool value) async {
    comfortable = value;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool('comfortable', value);
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  /// The text size choice closest to [value]; anything stored outside the choices snaps to the nearest one.
  static double snapTextScale(double value) {
    var best = textScaleChoices.first;
    for (final c in textScaleChoices) {
      if ((c - value).abs() < (best - value).abs()) best = c;
    }
    return best;
  }

  Future<void> setTextScale(double value) async {
    textScale = value;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setDouble('textScale', value);
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  Future<void> _savePref(String key, Object value) async {
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      switch (value) {
        case final bool v:
          await p.setBool(key, v);
        case final int v:
          await p.setInt(key, v);
        case final String v:
          await p.setString(key, v);
      }
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  Future<void> setHomeScreen(String id) {
    homeScreen = id;
    return _savePref('homeScreen', id);
  }

  Future<void> setDashboardRefreshMinutes(int minutes) {
    dashboardRefreshMinutes = minutes;
    return _savePref('dashboardRefreshMinutes', minutes);
  }

  Future<void> setRowsPerPage(int rows) {
    rowsPerPage = rows;
    AppPrefs.rowsPerPage = rows;
    return _savePref('rowsPerPage', rows);
  }

  Future<void> setReduceMotion(bool value) {
    reduceMotion = value;
    return _savePref('reduceMotion', value);
  }

  Future<void> setHighContrast(bool value) {
    highContrast = value;
    return _savePref('highContrast', value);
  }

  Future<void> setPrintPrompts(bool value) {
    printPrompts = value;
    AppPrefs.printPrompts = value;
    return _savePref('printPrompts', value);
  }

  /// Asks the server to set this user's idle lock and adopts the effective value it answers with (the administrator's cap may lower it).
  /// Returns that effective value; throws when the server refuses.
  Future<int> setIdleLockMinutes(int minutes) async {
    final r = await api.put('/api/auth/idle-lock', {'minutes': minutes}) as Map<String, dynamic>;
    _adoptIdle(r);
    notifyListeners();
    return idleLockMinutes;
  }

  DateTime? _activitySent;

  /// Tells the server the user is active (mouse, touch and key presses, not background polling) so it can enforce the idle lock too,
  /// not only this window. Sent at most once a minute, also when no lock is set; [force] sends it right away.
  void reportActivity({bool force = false}) {
    if (!loggedIn) return;
    final now = DateTime.now();
    if (!force && _activitySent != null && now.difference(_activitySent!) < const Duration(seconds: 60)) return;
    _activitySent = now;
    unawaited(api.post('/api/auth/activity', {}).then<void>((_) {}, onError: (Object e) => debugPrint('session: activity ping failed: $e')));
  }

  /// Saves the display name and email on the server; empty text clears a field.
  Future<void> saveProfile({String? displayName, String? email}) async {
    final r = await api.put('/api/auth/profile', {'displayName': displayName, 'email': email}) as Map<String, dynamic>;
    this.displayName = r['displayName'] as String?;
    this.email = r['email'] as String?;
    notifyListeners();
  }

  /// Signs every other device out; this one keeps working with fresh tokens.
  Future<void> revokeOtherSessions() async {
    final r = await api.post('/api/auth/sessions/revoke-others', {'refreshToken': api.refreshToken}) as Map<String, dynamic>;
    await _apply(r);
  }

  /// Changes the signed-in user's own password. The server signs every other session out and returns fresh tokens for this one.
  Future<void> changePassword(String current, String next) async {
    final r = await api.post('/api/auth/password', {'currentPassword': current, 'newPassword': next}) as Map<String, dynamic>;
    await _apply(r);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('themeMode', mode.name);
    } catch (e) {
      debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  Future<void> logout() async {
    final rt = api.refreshToken;
    if (rt != null) {
      // Best effort: revoke the refresh token server-side without blocking the UI.
      unawaited(api.post('/api/auth/logout', {'refreshToken': rt}).then<void>((_) {}, onError: (Object e) => debugPrint('session: logout revoke failed: $e')));
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
      } catch (e) {
        debugPrint('session: Local storage is best effort; the in-memory value stays: $e');
        // Local storage is best effort; the in-memory value stays.
      }
    }
    notifyListeners();
  }
}
