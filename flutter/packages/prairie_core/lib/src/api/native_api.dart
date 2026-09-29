import '../models/auth.dart';
import 'api_client.dart';
import 'api_error.dart';

/// Stable native API discovery data exposed by Prairie's /api/v2 surface.
class NativeSystemInfo {
  const NativeSystemInfo({
    required this.serverVersion,
    required this.apiMajor,
    required this.contractDigest,
    required this.openapiPath,
    required this.capabilitiesPath,
    required this.identityPath,
  });

  final String serverVersion;
  final int apiMajor;
  final String contractDigest;
  final String openapiPath;
  final String capabilitiesPath;
  final String identityPath;

  factory NativeSystemInfo.fromJson(Map<String, dynamic> json) {
    final links = json['links'] as Map<String, dynamic>? ?? const {};
    return NativeSystemInfo(
      serverVersion: json['server_version'] as String? ?? 'unavailable',
      apiMajor: (json['api_major'] as num?)?.toInt() ?? 0,
      contractDigest: json['contract_digest'] as String? ?? '',
      openapiPath: links['openapi'] as String? ?? '/api/v2/openapi.json',
      capabilitiesPath: links['capabilities'] as String? ?? '/api/v2/capabilities',
      identityPath: links['identity'] as String? ?? '/api/v2/system/identity',
    );
  }
}

/// v2 setup status. This is deliberately separate from the legacy
/// SetupStatusResponse because the native contract adds wizard_completed.
class NativeSetupStatus {
  const NativeSetupStatus({
    required this.needsSetup,
    required this.wizardCompleted,
  });

  final bool needsSetup;
  final bool wizardCompleted;

  factory NativeSetupStatus.fromJson(Map<String, dynamic> json) => NativeSetupStatus(
    needsSetup: json['needs_setup'] as bool? ?? false,
    wizardCompleted: json['wizard_completed'] as bool? ?? false,
  );
}

Future<NativeSystemInfo> fetchNativeSystemInfo(ApiClient client, String serverUrl) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(serverUrl: serverUrl),
    '/api/v2/system/info',
  );
  return NativeSystemInfo.fromJson(json);
}

Future<NativeSetupStatus> fetchNativeSetupStatus(ApiClient client, String serverUrl) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(serverUrl: serverUrl),
    '/api/v2/system/setup',
  );
  return NativeSetupStatus.fromJson(json);
}

/// Returns whether an error means the server simply predates the native v2
/// discovery surface. Other failures must not be hidden by falling back.
bool isNativeApiUnavailable(Object error) {
  return error is ApiError && (error.status == 404 || error.status == 405);
}
