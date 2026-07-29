import 'api_client.dart';
import 'api_error.dart';
import 'auth_api.dart';
import 'health_api.dart';

const _checkTimeout = Duration(seconds: 6);

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

/// User-facing message for transport/TLS/DNS failures (not HTTP error
/// bodies). Mirrors `networkFailureMessage`.
String networkFailureMessage(Object err) {
  if (err is ApiError) {
    if (err.code == 'timeout' || err.status == 408) {
      return 'Request timed out. Check the address and try again.';
    }
    return err.message.trim().isNotEmpty
        ? err.message.trim()
        : 'Could not reach a Prairie server at that address.';
  }
  return 'Could not reach a Prairie server at that address. Check http vs https and the port.';
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

  SetupStatusResponse setup;
  try {
    setup = await fetchSetupStatus(client, serverUrl, timeout: _checkTimeout);
  } catch (err) {
    return CheckServerFailure(networkFailureMessage(err));
  }

  String? serverName;
  try {
    final health = await fetchServerHealth(client, serverUrl);
    if (health != null && health.serverName.trim().isNotEmpty) serverName = health.serverName.trim();
  } catch (_) {
    // health is optional
  }

  return CheckServerSuccess(serverUrl: serverUrl, needsSetup: setup.needsSetup, serverName: serverName);
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
  return lastFailure ?? const CheckServerFailure('Could not reach a Prairie server at that address.');
}
