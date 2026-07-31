import 'api_client.dart';

/// Mirrors `HealthIdentity` from src/discovery/discover.ts.
class HealthIdentity {
  const HealthIdentity({required this.serverName, required this.serverId});
  final String serverName;
  final String serverId;

  /// Mirrors `parseHealth`. Only a `status` of ok/healthy/up counts as a
  /// live Prairie server.
  static HealthIdentity? parse(Object? data) {
    if (data is! Map) return null;
    final status = (data['status'] as String?)?.toLowerCase() ?? '';
    if (status != 'ok' && status != 'healthy' && status != 'up') return null;
    return HealthIdentity(
      serverName: data['server_name'] is String ? data['server_name'] as String : '',
      serverId: data['server_id'] is String ? data['server_id'] as String : '',
    );
  }
}

/// Mirrors `fetchServerHealth` from src/api/health.ts.
Future<HealthIdentity?> fetchServerHealth(ApiClient client, String serverUrl) async {
  try {
    final data = await client.request<dynamic>(
      ApiClientOptions(serverUrl: serverUrl, timeout: const Duration(seconds: 4)),
      '/api/v1/health',
    );
    return HealthIdentity.parse(data);
  } catch (_) {
    return null;
  }
}
