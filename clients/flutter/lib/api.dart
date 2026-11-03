import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Error answer from the API: HTTP [status], a user-facing [message] and per-field validation messages in [fieldErrors].
class ApiException implements Exception {
  ApiException(this.status, this.message, [this.fieldErrors = const {}]);

  final int status;
  final String message;
  final Map<String, List<String>> fieldErrors;

  @override
  String toString() => message;
}

/// One page of a paged list endpoint: [items] plus the [total] row count and the [skip]/[take] window.
class PageResult {
  PageResult(this.items, this.total, this.skip, this.take);

  factory PageResult.fromJson(Map<String, dynamic> j) =>
      PageResult((j['items'] as List).cast<Map<String, dynamic>>(), j['total'] as int, j['skip'] as int, j['take'] as int);

  final List<Map<String, dynamic>> items;
  final int total;
  final int skip;
  final int take;
}

/// HTTP client for the MetaGest API. Adds the bearer token, refreshes it silently on 401, sends the last seen version as `If-Match` on writes, and maps failures to [ApiException].
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
  /// Asked when the server refuses the refresh token. Return true after adopting a newer session (for example one another tab stored a moment ago) in [token] and [refreshToken].
  Future<bool> Function()? onRefreshRejected;
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

  /// True when the last [refresh] was refused by the server (the refresh token is unknown, expired or revoked), so the session is really over.
  /// False when it failed for any other reason (offline, timeout, 5xx, 429): the tokens are still good and the user stays signed in.
  bool refreshRejected = false;

  Future<bool> _doRefresh() async {
    final rt = refreshToken;
    refreshRejected = rt == null;
    if (rt == null) return false;
    try {
      final r = await _http
          .post(_uri('/api/auth/refresh'), headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'refreshToken': rt}))
          .timeout(requestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        refreshRejected = r.statusCode == 400 || r.statusCode == 401 || r.statusCode == 403;
        if (refreshRejected && await (onRefreshRejected?.call() ?? Future.value(false))) {
          refreshRejected = false;
          return true;
        }
        return false;
      }
      // Signed out while the request was in flight: do not bring the old session back.
      if (refreshToken != rt) return false;
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
        } else if (!refreshRejected && refreshToken != null) {
          // The server could not be asked (offline, restarting, busy): say so instead of ending a session that is still valid.
          throw ApiException(0, 'Servidor indisponível ($baseUrl)');
        }
      }
      return r;
    } on TimeoutException {
      // A write may have reached the server before the answer was lost; say so, so nobody repeats it blindly.
      throw ApiException(0, write ? 'O servidor demorou para responder. Confira se a ação foi registrada antes de repetir.' : 'O servidor demorou demais para responder. Tente novamente.');
    } on ApiException {
      rethrow;
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
      case 429:
        return ApiException(429, 'Muitas tentativas em pouco tempo. Aguarde um instante e tente de novo.');
    }
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final errors = <String, List<String>>{};
      (j['errors'] as Map<String, dynamic>?)?.forEach((k, v) => errors[k] = (v as List).cast<String>().map(translateServerText).toList());
      final msg = [_serverTitles[j['title']] ?? j['title'], j['detail']].whereType<String>().where((s) => s.isNotEmpty).map(translateServerText).join(': ');
      return ApiException(r.statusCode, errors.isNotEmpty ? 'Verifique os campos destacados' : (msg.isEmpty ? _fallback(r.statusCode) : msg), errors);
    } catch (_) {
      return ApiException(r.statusCode, _fallback(r.statusCode));
    }
  }

  /// Message for an error answer that carried no text of its own.
  static String _fallback(int status) => status >= 500 ? 'O servidor encontrou um problema. Tente de novo; se continuar, avise o suporte.' : 'Erro $status';
}

/// Generic problem titles the API sends in English (`Errors.cs`), shown in Portuguese.
const _serverTitles = {
  'Concurrent update': 'Registro alterado por outra pessoa',
  'Duplicate value': 'Valor já cadastrado',
  'Referenced record missing or still in use': 'Registro inexistente ou em uso',
  'Invalid value': 'Valor inválido',
  'Required value missing': 'Campo obrigatório vazio',
  'Value too long': 'Valor longo demais',
  'Cannot clear data': 'Não foi possível limpar os dados',
  'Cannot reverse': 'Não foi possível estornar',
};

/// Business-rule messages the API sends in English, by exact text.
const _serverMessages = {
  'Required': 'Obrigatório',
  'Cannot be negative': 'Não pode ser negativo',
  'Must not be negative': 'Não pode ser negativo',
  'Must be greater than zero': 'Deve ser maior que zero',
  'Must be positive': 'Deve ser positivo',
  'Not found': 'Não encontrado',
  'Between 0 and 100': 'Entre 0 e 100',
  'Between 0 and 24': 'Entre 0 e 24',
  'Rates between 0 and 100': 'Alíquotas entre 0 e 100',
  'Two-letter state': 'UF com duas letras',
  'Unknown UF': 'UF desconhecida',
  'Invalid email': 'E-mail inválido',
  'Email already used by another user': 'E-mail já usado por outro usuário',
  'Incorrect password': 'Senha incorreta',
  'Wrong password': 'Senha incorreta',
  'Must differ from the current password': 'Deve ser diferente da senha atual',
  'Too many wrong attempts; try again later': 'Muitas tentativas erradas. Tente de novo mais tarde.',
  'At least one active Admin must remain': 'Deve restar pelo menos um administrador ativo',
  'Unknown, inactive or third-party location': 'Local desconhecido, inativo ou de terceiros',
  'Required for rectangular tubes': 'Obrigatório para tubos retangulares',
  'Required for circular tubes': 'Obrigatório para tubos redondos',
  'Required for ICMS contributors': 'Obrigatório para contribuintes de ICMS',
  'Required when rejecting': 'Obrigatório ao recusar',
  'Required to enable fiscal emission': 'Obrigatório para ligar a emissão fiscal',
  'Full address required to enable fiscal emission': 'Endereço completo obrigatório para ligar a emissão fiscal',
  'Lot not found': 'Lote não encontrado',
  'Supplier not found': 'Fornecedor não encontrado',
  'Product not found': 'Produto não encontrado',
  'Material not found': 'Material não encontrado',
  'Processor not found': 'Beneficiador não encontrado',
  'Not an active session of this user': 'Não é uma sessão ativa deste usuário',
  'Not a backup file name': 'Não é o nome de um arquivo de backup',
  'Backup not found in the list published by the backup agent': 'Backup não encontrado na lista publicada pelo agente de backup',
  'Use HH:mm, for example 22:00': 'Use HH:mm, por exemplo 22:00',
  'Type RESTAURAR to confirm': 'Digite RESTAURAR para confirmar',
  'Type EXCLUIR to confirm': 'Digite EXCLUIR para confirmar',
  'Type your password to confirm the cancellation': 'Digite sua senha para confirmar o cancelamento',
  'Type your password to confirm the inutilização': 'Digite sua senha para confirmar a inutilização',
  'Must not exceed maxStock': 'Não pode passar do estoque máximo',
  'Must be a positive multiple of 10': 'Deve ser um múltiplo positivo de 10',
  'Wall thickness must be less than half the diameter': 'A espessura deve ser menor que a metade do diâmetro',
  'Finished plus scrap exceeds what was sent': 'Produzido mais sucata passa do que foi enviado',
  'Hourly, Every6Hours, Daily or Weekly': 'De hora em hora, a cada 6 horas, diário ou semanal',
  'Make a backup first: the newest one is missing or older than 1 hour': 'Faça um backup antes: o mais recente não existe ou tem mais de 1 hora',
  'NCM must have 8 digits': 'O NCM deve ter 8 dígitos',
  'At least one item': 'Inclua ao menos um item',
  'Customer not found': 'Cliente não encontrado',
  'Address does not belong to the customer': 'O local de entrega não é deste cliente',
  'Unknown or inactive payment term': 'Prazo de pagamento desconhecido ou inativo',
};

final _serverPatterns = <(RegExp, String Function(Match))>[
  (RegExp(r'^At least (\d+) characters$'), (m) => 'Pelo menos ${m[1]} caracteres'),
  (RegExp(r'^At most (\d+) characters$'), (m) => 'No máximo ${m[1]} caracteres'),
  (RegExp(r'^(\d+) digits$'), (m) => '${m[1]} dígitos'),
  (RegExp(r'^Product (.+) is blocked$'), (m) => 'O produto ${m[1]} está bloqueado'),
  (RegExp(r'^No price for (.+); give one or register it in the price list$'), (m) => 'Sem preço para ${m[1]}: informe um ou cadastre na tabela de preços'),
  (RegExp(r'^Customer (.+) is inactive$'), (m) => 'O cliente ${m[1]} está inativo'),
  (RegExp(r'^Must be greater than the last issued number \((\d+)\)$'), (m) => 'Deve ser maior que o último número emitido (${m[1]})'),
];

/// Portuguese text for an API message; text with no known translation (already Portuguese, or free text) is returned as it came.
String translateServerText(String s) {
  final exact = _serverMessages[s];
  if (exact != null) return exact;
  for (final (re, fn) in _serverPatterns) {
    final m = re.firstMatch(s);
    if (m != null) return fn(m);
  }
  return s;
}

/// Portuguese captions for the API field names that reach the user in validation messages.
const _fieldCaptions = {
  'customerId': 'Cliente',
  'paymentTermId': 'Prazo de pagamento',
  'customPaymentTerm': 'Prazo de pagamento',
  'addressId': 'Local de entrega',
  'lines': 'Itens',
  'leadTimeDays': 'Prazo de entrega',
  'ipiPercent': 'IPI',
  'icmsPercent': 'ICMS',
  'validityDays': 'Validade',
  'description': 'Descrição',
  'feasibilityId': 'Análise de viabilidade',
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
