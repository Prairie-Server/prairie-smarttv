import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_error.dart';

/// Mirrors `ApiClientOptions` from src/api/client.ts.
///
/// Difference from the TS version: there's no `localStorage` fallback for
/// `refreshToken` here — the caller (session holder) is expected to always
/// pass the current refresh token, and [onTokensRefreshed] is how it learns
/// about a renewed one. This is a simplification, not a behavior gap: the TS
/// fallback only existed because `client.ts` could be called before React
/// state caught up with storage.
class ApiClientOptions {
  const ApiClientOptions({
    required this.serverUrl,
    this.accessToken,
    this.refreshToken,
    this.profileId,
    this.profileToken,
    this.timeout = const Duration(seconds: 30),
    this.onUnauthorized,
    this.onTokensRefreshed,
  });

  final String serverUrl;
  final String? accessToken;
  final String? refreshToken;

  /// Active household profile — required by most /api/v1 browse routes.
  final String? profileId;

  /// PIN-verified profile token when the profile has a PIN.
  final String? profileToken;
  final Duration timeout;

  /// Called when the server rejects the session (401, or 403 with an
  /// auth-failure code). Not invoked for the login/refresh paths themselves,
  /// and skipped when a refresh token successfully renews the session.
  final void Function()? onUnauthorized;

  /// Fired after a successful access-token refresh so app state can catch up.
  final void Function(String accessToken, String? refreshToken)? onTokensRefreshed;

  ApiClientOptions withTokens({required String accessToken, String? refreshToken}) => ApiClientOptions(
    serverUrl: serverUrl,
    accessToken: accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    profileId: profileId,
    profileToken: profileToken,
    timeout: timeout,
    onUnauthorized: onUnauthorized,
    onTokensRefreshed: onTokensRefreshed,
  );
}

/// 403 response codes that indicate the access token/session is no longer valid.
const Set<String> _authForbiddenCodes = {
  'unauthorized',
  'invalid_token',
  'token_expired',
  'authentication_required',
  'auth_required',
  'session_expired',
};

/// Paths that must not trigger [ApiClientOptions.onUnauthorized] (a bad
/// login attempt must not clear the session/loop). Mirrors `isAuthLoginPath`.
bool isAuthLoginPath(String path) {
  final bare = path.split('?').first.replaceFirst(RegExp(r'/+$'), '');
  return bare == '/api/v1/auth/login' ||
      bare.endsWith('/auth/login') ||
      bare == '/api/v1/auth/refresh' ||
      bare.endsWith('/auth/refresh');
}

bool _shouldNotifyUnauthorized(int status, String? code) {
  if (status == 401) return true;
  if (status == 403 && code != null && _authForbiddenCodes.contains(code)) return true;
  return false;
}

String _joinUrl(String base, String path) {
  final normalizedBase = base.replaceFirst(RegExp(r'/+$'), '');
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$normalizedBase$normalizedPath';
}

/// True when [candidate] shares an origin with the connected Prairie server.
/// Mirrors `isSameServerOrigin`.
bool isSameServerOrigin(String serverUrl, String candidate) {
  try {
    final server = Uri.parse(serverUrl);
    final target = Uri.parse(candidate).hasScheme ? Uri.parse(candidate) : server.resolve(candidate);
    return target.scheme == server.scheme && target.authority == server.authority;
  } catch (_) {
    return false;
  }
}

/// Resolves a possibly-relative asset path (poster/backdrop/logo URL) against
/// the server base. Prairie's catalog responses return paths relative to the
/// server, same as `stream_url` — this is the non-token-bearing counterpart
/// to [buildStreamUrl] for plain image URLs.
String resolveAssetUrl(String serverUrl, String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return _joinUrl(serverUrl, path);
}

/// Resolves a `stream_url` from Prairie against the server base and attaches
/// the session token only when the resolved URL is same-origin with
/// [serverUrl]. Cross-origin absolute URLs (CDN, tuner, etc.) must not
/// receive the session bearer. Mirrors `buildStreamUrl`.
String buildStreamUrl(String serverUrl, String streamPath, String? token, [String? profileId]) {
  final base = streamPath.startsWith('http://') || streamPath.startsWith('https://')
      ? streamPath
      : _joinUrl(serverUrl, streamPath);

  if (!isSameServerOrigin(serverUrl, base)) return base;

  final params = <String, String>{};
  if (token != null) params['token'] = token;
  if (profileId != null) params['profile_id'] = profileId;
  if (params.isEmpty) return base;

  final separator = base.contains('?') ? '&' : '?';
  return '$base$separator${Uri(queryParameters: params).query}';
}

/// Dart port of src/api/client.ts's `apiRequest` + `refreshAccessToken`
/// (from src/api/auth.ts — consolidated here to avoid a client/auth import
/// cycle; the raw refresh call intentionally bypasses [request] so a failed
/// refresh can't recurse through the 401-handling path).
///
/// Single-flight refresh is a single static [Completer] shared process-wide,
/// mirroring the TS module-level `refreshInFlight` variable — this app has
/// exactly one active session at a time.
class ApiClient {
  ApiClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static Completer<_RefreshResult?>? _refreshInFlight;

  Map<String, String> _buildHeaders(ApiClientOptions options, {String? accessToken, bool hasBody = false}) {
    final headers = <String, String>{};
    if (hasBody) headers['Content-Type'] = 'application/json';
    final token = accessToken ?? options.accessToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (options.profileId != null) headers['X-Profile-Id'] = options.profileId!;
    if (options.profileToken != null) headers['X-Profile-Token'] = options.profileToken!;
    headers['X-Prairie-Device-Platform'] = 'smarttv';
    headers['X-Prairie-Device-Name'] = 'Prairie Smart TV';
    // TODO: port getImageFormats()'s capability-detected preference list
    // (src/lib/imageFormats.ts) once image loading is ported; avif/webp
    // covers what Flutter's built-in codecs decode today.
    headers['X-Prairie-Image-Formats'] = 'avif,webp';
    return headers;
  }

  Future<Response<dynamic>> _performFetch(
    ApiClientOptions options,
    String path, {
    required String method,
    Object? body,
    String? accessToken,
  }) {
    final headers = _buildHeaders(options, accessToken: accessToken, hasBody: body != null);
    return _dio.request<dynamic>(
      _joinUrl(options.serverUrl, path),
      data: body,
      // Plain, not the default json ResponseType: a non-JSON error body
      // (proxy/5xx HTML page, empty string, ...) must fall back to
      // statusMessage rather than blow up before we can inspect status.
      // Mirrors the TS client's `try { await response.json() } catch {}`.
      options: Options(
        method: method,
        headers: headers,
        sendTimeout: options.timeout,
        receiveTimeout: options.timeout,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    );
  }

  /// Best-effort JSON decode of a plain-text response body; null when the
  /// body is empty or not valid JSON.
  Object? _tryDecodeJson(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  ({String? message, String? code, Object? body}) _parseError(Response<dynamic> response) {
    final data = _tryDecodeJson(response.data);
    String? message;
    String? code;
    if (data is Map) {
      final record = data.cast<String, dynamic>();
      if (record['message'] is String) message = record['message'] as String;
      if (message == null && record['error'] is String) message = record['error'] as String;
      if (record['code'] is String) code = record['code'] as String;
    }
    return (message: message ?? response.statusMessage ?? 'HTTP ${response.statusCode}', code: code, body: data);
  }

  Future<_RefreshResult?> _tryRefreshSession(ApiClientOptions options) {
    final refreshToken = options.refreshToken;
    if (refreshToken == null) return Future.value(null);

    return (_refreshInFlight ??= () {
      final completer = Completer<_RefreshResult?>();
      _rawRefresh(options.serverUrl, refreshToken)
          .then((result) {
            if (result != null) {
              try {
                options.onTokensRefreshed?.call(result.accessToken, result.refreshToken);
              } catch (_) {
                // Listener errors must not mask the refresh result.
              }
            }
            completer.complete(result);
          })
          .catchError((_) {
            completer.complete(null);
          })
          .whenComplete(() => _refreshInFlight = null);
      return completer;
    }()).future;
  }

  Future<_RefreshResult?> _rawRefresh(String serverUrl, String refreshToken) async {
    try {
      final response = await _dio.post<dynamic>(
        _joinUrl(serverUrl, '/api/v1/auth/refresh'),
        data: jsonEncode({'refresh_token': refreshToken}),
        options: Options(headers: {'Content-Type': 'application/json'}, validateStatus: (_) => true),
      );
      if (response.statusCode == null || response.statusCode! >= 400) return null;
      final data = response.data;
      if (data is! Map || data['access_token'] is! String) return null;
      return _RefreshResult(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Mirrors `apiRequest<T>`. [T] should be `Map<String, dynamic>`,
  /// `List<dynamic>`, or another JSON-decodable shape — callers are
  /// responsible for the same unchecked cast the TS generic performs.
  Future<T> request<T>(ApiClientOptions options, String path, {String method = 'GET', Object? body}) async {
    var response = await _performFetch(options, path, method: method, body: body);

    if (response.statusCode == null || response.statusCode! >= 400) {
      final peek = _parseError(response);
      final authFailure =
          _shouldNotifyUnauthorized(response.statusCode ?? 0, peek.code) && !isAuthLoginPath(path);

      if (authFailure) {
        final refreshed = await _tryRefreshSession(options);
        if (refreshed != null) {
          response = await _performFetch(
            options,
            path,
            method: method,
            body: body,
            accessToken: refreshed.accessToken,
          );
          if (response.statusCode != null && response.statusCode! < 400) {
            if (response.statusCode == 204) return null as T;
            return _tryDecodeJson(response.data) as T;
          }
          final retryError = _parseError(response);
          if (_shouldNotifyUnauthorized(response.statusCode ?? 0, retryError.code)) {
            try {
              options.onUnauthorized?.call();
            } catch (_) {
              // Logout handlers must not mask the ApiError below.
            }
          }
          throw ApiError(retryError.message!, response.statusCode ?? 0, retryError.code, retryError.body);
        }

        try {
          options.onUnauthorized?.call();
        } catch (_) {
          // Logout handlers must not mask the ApiError below.
        }
      }

      throw ApiError(peek.message!, response.statusCode ?? 0, peek.code, peek.body);
    }

    if (response.statusCode == 204) return null as T;
    return _tryDecodeJson(response.data) as T;
  }
}

class _RefreshResult {
  const _RefreshResult({required this.accessToken, this.refreshToken});
  final String accessToken;
  final String? refreshToken;
}
