import '../models/auth.dart';
import '../models/library.dart';
import '../models/watch_detail.dart' show idFromJson;
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
    '/api/v2/user/libraries',
  );

  List<dynamic> raw;
  if (data is List) {
    raw = data;
  } else if (data is Map && (data['items'] ?? data['libraries']) is List) {
    raw = (data['items'] ?? data['libraries']) as List<dynamic>;
  } else {
    raw = const [];
  }

  // v2 library ids are opaque strings; Prairie's are integers, and a library
  // without one can't be browsed, so it is dropped.
  return raw.cast<Map<String, dynamic>>().where((m) => idFromJson(m['id']) != null).map((m) {
    return Library(
      id: idFromJson(m['id'])!,
      name: m['name'] as String,
      type: m['type'] as String,
      sortOrder: m['sort_order'] as int?,
      posterUrl: m['poster_url'] as String?,
    );
  }).toList();
}
