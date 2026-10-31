import 'dart:async';
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
  String? refreshToken;

  /// Called with the refresh response (same shape as login) after a successful silent refresh.
  void Function(Map<String, dynamic> session)? onRefreshed;
  Future<bool>? _refreshing;
  final http.Client _http;
  final _versions = <String, String>{};
  /// Auth endpoints that never trigger a silent refresh (a 401 there is a real answer); /api/auth/me and the rest may refresh.
  static const _noRefresh = ['/api/auth/login', '/api/auth/refresh', '/api/auth/logout'];
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

  Future<dynamic> post(String path, Object body) => _send(path, () => _http.post(_uri(path), headers: _writeHeaders(path), body: jsonEncode(body)), write: true);

  Future<dynamic> put(String path, Object body) => _send(path, () => _http.put(_uri(path), headers: _writeHeaders(path), body: jsonEncode(body)), write: true);

  Future<dynamic> delete(String path) => _send(path, () => _http.delete(_uri(path), headers: _writeHeaders(path)), write: true);

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
  }, write: true, timeout: transferTimeout);

  /// Raw bytes of a file endpoint. Goes through the same silent refresh as every other call, so a PDF opened after the access token expired still works.
  Future<Uint8List> download(String path) async {
    final r = await _call(path, () => _http.get(_uri(path), headers: {if (token != null) 'Authorization': 'Bearer $token'}), timeout: transferTimeout);
    if (r.statusCode == 401 && token != null) onUnauthorized?.call();
    if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
    throw _error(r, path);
  }

  /// Exchanges the refresh token for a new session. Concurrent callers share one request.
  Future<bool> refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final rt = refreshToken;
    if (rt == null) return false;
    try {
      final r = await _http
          .post(_uri('/api/auth/refresh'), headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'refreshToken': rt}))
          .timeout(requestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) return false;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      token = j['token'] as String;
      refreshToken = j['refreshToken'] as String?;
      onRefreshed?.call(j);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// How long a normal request may take before the user is told instead of watching a spinner forever; files get longer.
  static const requestTimeout = Duration(seconds: 20);
  static const transferTimeout = Duration(seconds: 90);

  Future<http.Response> _call(String path, Future<http.Response> Function() call, {bool write = false, Duration timeout = requestTimeout}) async {
    // Signing in changes nothing a user could duplicate, so a lost login is simply "server unavailable".
    if (path.startsWith('/api/auth/')) write = false;
    try {
      var r = await call().timeout(timeout);
      if (r.statusCode == 401 && token != null && !_noRefresh.any(path.startsWith)) {
        if (await refresh()) {
          r = await call().timeout(timeout);
        }
      }
      return r;
    } on TimeoutException {
      // A write may have reached the server before the answer was lost; say so, so nobody repeats it blindly.
      throw ApiException(0, write ? 'O servidor demorou para responder. Confira se a ação foi registrada antes de repetir.' : 'O servidor demorou demais para responder. Tente novamente.');
    } catch (e) {
      throw ApiException(0, write ? 'Conexão perdida. Confira se a ação foi registrada antes de repetir. ($baseUrl)' : 'Servidor indisponível ($baseUrl)');
    }
  }

  Future<dynamic> _send(String path, Future<http.Response> Function() call, {bool write = false, Duration timeout = requestTimeout}) async {
    final r = await _call(path, call, write: write, timeout: timeout);
    if (r.statusCode == 401 && token != null) onUnauthorized?.call();
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final tag = r.headers['etag'];
      final k = _versionKey(path);
      if (tag != null && k != null) _versions[k] = tag;
      return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    }
    throw _error(r, path);
  }

  ApiException _error(http.Response r, [String path = '']) {
    switch (r.statusCode) {
      case 401:
        // A wrong password only exists on the login call; anywhere else a 401 means the session ended.
        return ApiException(401, path.startsWith('/api/auth/login') ? 'Usuário ou senha inválidos' : 'Sessão expirada. Entre novamente.');
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

/// Portuguese captions for the API field names that reach the user in validation messages.
const _fieldCaptions = {
  'customerId': 'Cliente',
  'paymentTermId': 'Prazo',
  'productId': 'Produto',
  'materialId': 'Material',
  'supplierId': 'Fornecedor',
  'quantity': 'Quantidade',
  'unitPrice': 'Preço unitário',
  'deliveryDate': 'Data de entrega',
  'validUntil': 'Validade',
  'discountPercent': 'Desconto',
  'notes': 'Observações',
  'customerPo': 'Pedido do cliente',
  'name': 'Nome',
  'code': 'Código',
  'email': 'E-mail',
  'ncm': 'NCM',
  'password': 'Senha',
  'currentPassword': 'Senha atual',
  'newPassword': 'Nova senha',
  'username': 'Usuário',
};

String _humanize(String key) {
  final cap = _fieldCaptions[key];
  if (cap != null) return cap;
  final words = key.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}').toLowerCase();
  return words.isEmpty ? key : '${words[0].toUpperCase()}${words.substring(1)}';
}

String fieldLabel(String key) {
  final m = RegExp(r'^[Ll]ines\[(\d+)\]\.?(.*)$').firstMatch(key);
  if (m != null) return 'Linha ${int.parse(m[1]!) + 1}${m[2]!.isEmpty ? '' : ' · ${_humanize(m[2]!)}'}';
  return _humanize(key);
}

String describeError(ApiException e) {
  if (e.fieldErrors.isEmpty) return e.message;
  return e.fieldErrors.entries.map((x) => '${fieldLabel(x.key)}: ${x.value.join('; ')}').join('\n');
}

/// Message safe to show a user for any thrown object; raw exception text never leaks.
String friendlyError(Object e) {
  if (e is ApiException) return describeError(e);
  if (e is FormatException || e is TypeError) return 'Resposta inesperada do servidor. Atualize a tela e tente de novo.';
  return 'Não foi possível concluir. Tente novamente.';
}
