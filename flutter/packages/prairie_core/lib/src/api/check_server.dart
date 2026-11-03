import 'api_client.dart';
import 'api_error.dart';
import 'health_api.dart';
import 'native_api.dart';

const _checkTimeout = Duration(seconds: 6);

const _notPrairieMessage = 'That address is not a Prairie server. Check the URL and port.';

/// Mirrors `buildManualUrlCandidates` from src/api/checkServer.ts: an
/// explicit scheme keeps only that scheme; a bare host tries https then http.
List<String> buildManualUrlCandidates(String raw) {
  final trimmed = raw.trim().replaceFirst(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) return [];

  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
    return [trimmed];
  }

  final withoutSlashes = trimmed.replaceFirst(RegExp(r'^/+'), '');
  return ['https://$withoutSlashes', 'http://$withoutSlashes'];
}

/// Apple TV's wording for an address where no Prairie server answered.
const couldNotReachPrairieMessage = 'Could not reach a Prairie server at that address.';

/// The message the server itself sent with [err], or null for a bare HTTP
/// error (a 404 or 502 page from something that isn't Prairie), whose
/// [ApiError.message] is only the HTTP status text.
String? serverProvidedMessage(ApiError err) {
  final body = err.body;
  if (body is! Map) return null;
  for (final key in const ['message', 'error', 'detail', 'title']) {
    final value = body[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// User-facing message for a failed server probe. Mirrors Android's
/// `probeTvServerSetupCandidates` (#758, #771): an HTTP error keeps the
/// server's own message; a bare HTTP error, a timeout or a transport / TLS /
/// DNS failure says "Could not reach a Prairie server at that address."
String networkFailureMessage(Object err) {
  if (err is ApiError && err.status > 0 && err.code != 'timeout') {
    final message = serverProvidedMessage(err);
    if (message != null) return 'Could not reach server: $message';
  }
  return couldNotReachPrairieMessage;
}

sealed class CheckServerResult {
  const CheckServerResult();
}

class CheckServerSuccess extends CheckServerResult {
  const CheckServerSuccess({required this.serverUrl, required this.needsSetup, this.serverName});
  final String serverUrl;
  final bool needsSetup;
  final String? serverName;
}

class CheckServerFailure extends CheckServerResult {
  const CheckServerFailure(this.message);
  final String message;
}

/// Probes a candidate server before showing the login screen: requires
/// GET /api/v1/auth/setup, with health as best-effort for a display name.
/// Mirrors `checkServer`.
Future<CheckServerResult> checkServer(ApiClient client, String serverUrl) async {
  Uri parsed;
  try {
    parsed = Uri.parse(serverUrl);
  } catch (_) {
    return const CheckServerFailure('Enter a valid Prairie server address.');
  }
  if (parsed.scheme != 'http' && parsed.scheme != 'https') {
    return const CheckServerFailure('Server URL must use http or https.');
  }
  if (parsed.userInfo.isNotEmpty) {
    return const CheckServerFailure('Server URL must not include credentials.');
  }

  bool needsSetup;
  try {
    // Prefer the stable native API's public discovery surface. Older Prairie
    // servers keep the frozen v1 bridge, so only a missing v2 route falls back.
    Object? data;
    try {
      data = await client.request<dynamic>(ApiClientOptions(serverUrl: serverUrl), '/api/v2/system/setup');
    } catch (err) {
      if (!isNativeApiUnavailable(err)) rethrow;
      data = await client.request<dynamic>(
        ApiClientOptions(serverUrl: serverUrl, timeout: _checkTimeout),
        '/api/v1/auth/setup',
      );
    }
    // Any web server can answer 200; only Prairie returns a setup payload.
    if (data is! Map || data['needs_setup'] is! bool) return const CheckServerFailure(_notPrairieMessage);
    needsSetup = data['needs_setup'] as bool;
  } catch (err) {
    // Neither setup route exists: something is listening, but it isn't
    // Prairie. A bare 404 with no message reads as Apple TV's "Could not
    // reach a Prairie server" (#771).
    if (isNativeApiUnavailable(err)) {
      return CheckServerFailure(
        serverProvidedMessage(err as ApiError) == null ? couldNotReachPrairieMessage : _notPrairieMessage,
      );
    }
    return CheckServerFailure(networkFailureMessage(err));
  }

  String? serverName;
  try {
    final health = await fetchServerHealth(client, serverUrl);
    if (health != null && health.serverName.trim().isNotEmpty) serverName = health.serverName.trim();
  } catch (_) {
    // health is optional
  }

  return CheckServerSuccess(serverUrl: serverUrl, needsSetup: needsSetup, serverName: serverName);
}

/// Tries candidates in order until one responds to /auth/setup. Mirrors
/// `checkServerCandidates`.
Future<CheckServerResult> checkServerCandidates(ApiClient client, List<String> candidates) async {
  if (candidates.isEmpty) {
    return const CheckServerFailure('Enter a valid Prairie server address.');
  }
  CheckServerFailure? lastFailure;
  for (final candidate in candidates) {
    final result = await checkServer(client, candidate);
    if (result is CheckServerSuccess) return result;
    lastFailure = result as CheckServerFailure;
  }
  return lastFailure ?? const CheckServerFailure(couldNotReachPrairieMessage);
}
