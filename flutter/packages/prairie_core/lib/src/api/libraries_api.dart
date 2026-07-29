import '../models/auth.dart';
import '../models/library.dart';
import 'api_client.dart';

/// Mirrors `fetchLibraries` from src/api/libraries.ts. Response caching
/// (`cachedRequest`/`CACHE_TTL_MS`) isn't ported yet — see `requestCache.ts`
/// in the porting backlog.
Future<List<Library>> fetchLibraries(ApiClient client, PrairieSession session) async {
  final data = await client.request<dynamic>(
    ApiClientOptions(
      serverUrl: session.serverUrl,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      profileId: session.profileId,
      profileToken: session.profileToken,
    ),
    '/api/v1/user/libraries',
  );

  List<dynamic> raw;
  if (data is List) {
    raw = data;
  } else if (data is Map && data['libraries'] is List) {
    raw = data['libraries'] as List<dynamic>;
  } else {
    raw = const [];
  }

  return raw.map((j) {
    final m = j as Map<String, dynamic>;
    return Library(
      id: m['id'] as int,
      name: m['name'] as String,
      type: m['type'] as String,
      sortOrder: m['sort_order'] as int?,
      posterUrl: m['poster_url'] as String?,
    );
  }).toList();
}
