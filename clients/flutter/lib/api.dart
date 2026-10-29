import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.message, [this.fieldErrors = const {}]);

  final int status;
  final String message;
  final Map<String, List<String>> fieldErrors;

  @override
  String toString() => message;
}

class PageResult {
  PageResult(this.items, this.total, this.skip, this.take);

  factory PageResult.fromJson(Map<String, dynamic> j) =>
      PageResult((j['items'] as List).cast<Map<String, dynamic>>(), j['total'] as int, j['skip'] as int, j['take'] as int);

  final List<Map<String, dynamic>> items;
  final int total;
  final int skip;
  final int take;
}

class ApiClient {
  // ignore: prefer_initializing_formals
  ApiClient({required String baseUrl, this.token, http.Client? client, this.onUnauthorized}) : _baseUrl = baseUrl, _http = client ?? http.Client();

  String _baseUrl;
  String get baseUrl => _baseUrl;
  set baseUrl(String v) {
    if (v != _baseUrl) _versions.clear();
    _baseUrl = v;
  }

  String? token;
  void Function()? onUnauthorized;
  final http.Client _http;
  final _versions = <String, String>{};
  static final _idKey = RegExp(r'^(.*?/\d+)(?:[/?]|$)');

  static String? _versionKey(String path) => _idKey.firstMatch(path)?.group(1);

  void clearVersions() => _versions.clear();

  Map<String, String> _writeHeaders(String path) {
    final k = _versionKey(path);
    final tag = k == null ? null : _versions[k];
    return {..._headers, 'If-Match': ?tag};
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final q = query?.map((k, v) => MapEntry(k, '$v'))?..removeWhere((_, v) => v.isEmpty || v == 'null');
    return Uri.parse('$base$path').replace(queryParameters: q == null || q.isEmpty ? null : q);
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json', 'Accept': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) => _send(path, () => _http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, Object body) => _send(path, () => _http.post(_uri(path), headers: _writeHeaders(path), body: jsonEncode(body)));

  Future<dynamic> put(String path, Object body) => _send(path, () => _http.put(_uri(path), headers: _writeHeaders(path), body: jsonEncode(body)));

  Future<dynamic> delete(String path) => _send(path, () => _http.delete(_uri(path), headers: _writeHeaders(path)));

  Future<PageResult> list(String path, {String? q, int skip = 0, int take = 50, Map<String, dynamic> query = const {}}) async {
    final r = await get(path, {...query, 'q': q, 'skip': skip, 'take': take});
    if (r is List) return PageResult(r.cast<Map<String, dynamic>>(), r.length, 0, r.length);
    return PageResult.fromJson(r as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> listAll(String path, {Map<String, dynamic> query = const {}}) async {
    final all = <Map<String, dynamic>>[];
    var skip = 0;
    while (true) {
      final page = await list(path, skip: skip, take: 500, query: query);
      all.addAll(page.items);
      skip += page.items.length;
      if (page.items.isEmpty || skip >= page.total) return all;
    }
  }

  /// Multipart upload of a single file; returns the decoded JSON response.
  Future<dynamic> upload(String path, String field, String filename, Uint8List bytes) => _send(path, () async {
    final req = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll({'Accept': 'application/json', if (token != null) 'Authorization': 'Bearer $token'})
      ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename));
    return http.Response.fromStream(await _http.send(req));
  });

  /// Raw bytes of a file endpoint.
  Future<Uint8List> download(String path) async {
    http.Response r;
    try {
      r = await _http.get(_uri(path), headers: {if (token != null) 'Authorization': 'Bearer $token'});
    } catch (e) {
      throw ApiException(0, 'Servidor indisponível ($baseUrl)');
    }
    if (r.statusCode == 401 && token != null) onUnauthorized?.call();
    if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
    throw _error(r);
  }

  Future<dynamic> _send(String path, Future<http.Response> Function() call) async {
    http.Response r;
    try {
      r = await call();
    } catch (e) {
      throw ApiException(0, 'Servidor indisponível ($baseUrl)');
    }
    if (r.statusCode == 401 && token != null) onUnauthorized?.call();
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final tag = r.headers['etag'];
      final k = _versionKey(path);
      if (tag != null && k != null) _versions[k] = tag;
      return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    }
    throw _error(r);
  }

  ApiException _error(http.Response r) {
    switch (r.statusCode) {
      case 401:
        return ApiException(401, 'Usuário ou senha inválidos, ou sessão expirada');
      case 403:
        return ApiException(403, 'Sem permissão para esta ação');
      case 412:
        return ApiException(412, 'O registro foi alterado por outra pessoa; recarregue e tente novamente');
      case 404:
        return ApiException(404, 'Registro não encontrado');
    }
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final errors = <String, List<String>>{};
      (j['errors'] as Map<String, dynamic>?)?.forEach((k, v) => errors[k] = (v as List).cast<String>());
      final msg = [j['title'], j['detail']].whereType<String>().where((s) => s.isNotEmpty).join(': ');
      return ApiException(r.statusCode, errors.isNotEmpty ? 'Verifique os campos destacados' : (msg.isEmpty ? 'Erro ${r.statusCode}' : msg), errors);
    } catch (_) {
      return ApiException(r.statusCode, 'Erro ${r.statusCode}');
    }
  }
}
