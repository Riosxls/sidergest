import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Forms register a saver here; the app calls [saveAll] when the session is locked or expires, before the open forms are closed,
/// so what the user was typing can be offered again after signing in.
class DraftRegistry {
  static final _savers = <void Function()>{};

  static void register(void Function() saver) => _savers.add(saver);

  static void unregister(void Function() saver) => _savers.remove(saver);

  /// Runs every saver. Each one reads its form right away, so it is safe to close the forms straight after.
  static void saveAll() {
    for (final s in _savers.toList()) {
      s();
    }
  }
}

/// Unsent form contents kept on this computer for a day.
class DraftStore {
  static const _key = 'formDrafts';
  static const keepFor = Duration(hours: 24);

  static Future<Map<String, dynamic>> _all() async {
    final p = await SharedPreferences.getInstance();
    final raw = jsonDecode(p.getString(_key) ?? '{}');
    return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>?> load(String name) async {
    try {
      final e = (await _all())[name];
      if (e is! Map<String, dynamic>) return null;
      final at = DateTime.tryParse('${e['at']}');
      if (at == null || DateTime.now().difference(at) > keepFor) return null;
      final data = e['data'];
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('drafts: Local storage is best effort; no draft is offered: $e');
      return null;
    }
  }

  static Future<void> save(String name, Map<String, dynamic> data) async {
    try {
      final all = await _all();
      all.removeWhere((_, v) => v is! Map || (DateTime.tryParse('${v['at']}')?.isBefore(DateTime.now().subtract(keepFor)) ?? true));
      all[name] = {'at': DateTime.now().toIso8601String(), 'data': data};
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(all));
    } catch (e) {
      debugPrint('drafts: Local storage is best effort; the draft is not kept: $e');
    }
  }

  static Future<void> clear(String name) async {
    try {
      final all = await _all();
      if (all.remove(name) != null) await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(all));
    } catch (e) {
      debugPrint('drafts: Local storage is best effort; nothing to clear: $e');
    }
  }
}
