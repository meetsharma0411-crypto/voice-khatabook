import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../auth/auth_token_store.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.body});
  final int statusCode;
  final String message;
  final Object? body;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Reusable JSON API client with one coordinated JWT refresh and one retry.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokenStore,
    HttpClient? httpClient,
    this.onUnauthenticated,
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _httpClient = httpClient ?? HttpClient();

  final Uri _baseUri;
  final AuthTokenStore tokenStore;
  final HttpClient _httpClient;
  final void Function()? onUnauthenticated;
  Future<bool>? _refreshInFlight;

  Future<Object?> get(String path) => _send(method: 'GET', path: path);

  Future<Object?> patch(String path, {required Object body}) =>
      _send(method: 'PATCH', path: path, body: body);

  Future<Object?> post(String path, {Object? body, String? idempotencyKey}) =>
      _send(
        method: 'POST',
        path: path,
        body: body,
        idempotencyKey: idempotencyKey,
      );

  /// Authenticated multipart file upload using the same JWT refresh/retry path.
  Future<Object?> postMultipartFile({
    required String path,
    required File file,
    required String fileField,
    required Map<String, String> fields,
    String? idempotencyKey,
  }) async {
    final tokens = await tokenStore.readTokens();
    var response = await _requestMultipart(
      path,
      file: file,
      fileField: fileField,
      fields: fields,
      idempotencyKey: idempotencyKey,
      accessToken: tokens?.access,
    );
    if (response.statusCode == HttpStatus.unauthorized) {
      if (await _refreshAccessToken(tokens?.access)) {
        final refreshed = await tokenStore.readTokens();
        response = await _requestMultipart(
          path,
          file: file,
          fileField: fileField,
          fields: fields,
          idempotencyKey: idempotencyKey,
          accessToken: refreshed?.access,
        );
      } else {
        await tokenStore.clearTokens();
        onUnauthenticated?.call();
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'Request failed',
        body: response.body,
      );
    }
    return response.body;
  }

  Future<_ApiResponse> _requestMultipart(
    String path, {
    required File file,
    required String fileField,
    required Map<String, String> fields,
    required String? idempotencyKey,
    required String? accessToken,
  }) async {
    final boundary = 'khata-${DateTime.now().microsecondsSinceEpoch}';
    final request = await _httpClient.openUrl('POST', _baseUri.resolve(path));
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    if (idempotencyKey != null) {
      request.headers.set('Idempotency-Key', idempotencyKey);
    }
    if (accessToken != null && accessToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
    }

    final body = BytesBuilder(copy: false);
    void field(String name, String value) {
      body.add(utf8.encode('--$boundary\r\n'));
      body.add(
        utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'),
      );
      body.add(utf8.encode('$value\r\n'));
    }

    for (final entry in fields.entries) {
      field(entry.key, entry.value);
    }
    final filename = file.uri.pathSegments.isEmpty
        ? 'voice.m4a'
        : file.uri.pathSegments.last.replaceAll(RegExp(r'["\\\r\n]'), '_');
    final extension = filename.toLowerCase().split('.').last;
    final mime = switch (extension) {
      'wav' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      'ogg' || 'opus' => 'audio/ogg',
      'webm' => 'audio/webm',
      'aac' => 'audio/aac',
      '3gp' => 'audio/3gpp',
      _ => 'audio/m4a',
    };
    body.add(utf8.encode('--$boundary\r\n'));
    body.add(
      utf8.encode(
        'Content-Disposition: form-data; name="$fileField"; filename="$filename"\r\n',
      ),
    );
    body.add(utf8.encode('Content-Type: $mime\r\n\r\n'));
    body.add(await file.readAsBytes());
    body.add(utf8.encode('\r\n--$boundary--\r\n'));
    final bytes = body.takeBytes();
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = text;
      }
    }
    return _ApiResponse(response.statusCode, decoded);
  }

  /// Sends auth endpoints without attaching an old access token or refreshing.
  Future<Object?> postUnauthenticated(String path, {required Object body}) =>
      _send(
        path: path,
        method: 'POST',
        body: body,
        includeAuth: false,
        allowRefresh: false,
      );

  Future<Object?> _send({
    required String method,
    required String path,
    Object? body,
    String? idempotencyKey,
    bool includeAuth = true,
    bool allowRefresh = true,
  }) async {
    final requestTokens = includeAuth ? await tokenStore.readTokens() : null;
    final response = await _request(
      method,
      path,
      body: body,
      idempotencyKey: idempotencyKey,
      includeAuth: includeAuth,
      accessToken: requestTokens?.access,
    );
    if (response.statusCode == HttpStatus.unauthorized && includeAuth) {
      if (allowRefresh && await _refreshAccessToken(requestTokens?.access)) {
        return _send(
          method: method,
          path: path,
          body: body,
          idempotencyKey: idempotencyKey,
          includeAuth: true,
          allowRefresh: false,
        );
      }
      await tokenStore.clearTokens();
      onUnauthenticated?.call();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'Request failed',
        body: response.body,
      );
    }
    return response.body;
  }

  Future<_ApiResponse> _request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
    bool includeAuth = true,
    String? accessToken,
  }) async {
    final request = await _httpClient.openUrl(method, _baseUri.resolve(path));
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (body != null) request.headers.contentType = ContentType.json;
    if (idempotencyKey != null) {
      request.headers.set('Idempotency-Key', idempotencyKey);
    }
    if (includeAuth && accessToken != null && accessToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
    }
    if (body != null) {
      final bodyBytes = utf8.encode(jsonEncode(body));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = text;
      }
    }
    return _ApiResponse(response.statusCode, decoded);
  }

  Future<bool> _refreshAccessToken(String? failedAccessToken) {
    final pending = _refreshInFlight;
    if (pending != null) return pending;

    late final Future<bool> refresh;
    refresh = _performRefresh(failedAccessToken).whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
    _refreshInFlight = refresh;
    return refresh;
  }

  Future<bool> _performRefresh(String? failedAccessToken) async {
    final current = await tokenStore.readTokens();
    if (current == null || current.refresh.isEmpty) return false;
    // A parallel request may already have refreshed this exact access token.
    if (failedAccessToken != null && current.access != failedAccessToken) {
      return true;
    }
    final response = await _request(
      'POST',
      'auth/token/refresh/',
      body: {'refresh': current.refresh},
      includeAuth: false,
    );
    if (response.statusCode == HttpStatus.badRequest ||
        response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      await tokenStore.clearTokens();
      return false;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'Token refresh failed',
        body: response.body,
      );
    }
    if (response.body is! Map) {
      throw const FormatException('The token refresh response was invalid.');
    }
    final payload = response.body as Map;
    final access = payload['access'];
    final refresh = payload['refresh'];
    if (access is! String || access.isEmpty) {
      throw const FormatException(
        'The token refresh response contained no access token.',
      );
    }
    await tokenStore.saveTokens(
      AuthTokens(
        access: access,
        refresh: refresh is String && refresh.isNotEmpty
            ? refresh
            : current.refresh,
      ),
    );
    return true;
  }

  void close({bool force = false}) => _httpClient.close(force: force);
}

class _ApiResponse {
  const _ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final Object? body;
}
