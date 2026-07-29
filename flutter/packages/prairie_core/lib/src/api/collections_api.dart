import '../models/auth.dart';
import '../models/collection.dart';
import 'api_client.dart';

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

CollectionCard _cardFromJson(Map<String, dynamic> json, {int? libraryId}) => CollectionCard(
  id: json['id'] as String,
  title: (json['title'] as String?) ?? (json['name'] as String?),
  name: json['name'] as String?,
  posterUrl: json['poster_url'] as String?,
  itemCount: json['item_count'] as int?,
  featured: json['featured'] as bool?,
  libraryId: libraryId ?? json['library_id'] as int?,
);

/// Mirrors `fetchLibraryCollections` from src/api/collections.ts.
Future<List<CollectionCard>> fetchLibraryCollections(
  ApiClient client,
  PrairieSession session,
  int libraryId,
) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v1/library/$libraryId/collections',
  );
  final out = <CollectionCard>[];
  for (final group in (json['groups'] as List<dynamic>? ?? [])) {
    for (final card in ((group as Map<String, dynamic>)['collections'] as List<dynamic>? ?? [])) {
      out.add(_cardFromJson(card as Map<String, dynamic>, libraryId: libraryId));
    }
  }
  final ungrouped = json['ungrouped'] as Map<String, dynamic>?;
  for (final card in (ungrouped?['collections'] as List<dynamic>? ?? [])) {
    out.add(_cardFromJson(card as Map<String, dynamic>, libraryId: libraryId));
  }
  return out;
}

/// Mirrors `fetchPersonalCollections` from src/api/collections.ts.
Future<List<CollectionCard>> fetchPersonalCollections(ApiClient client, PrairieSession session) async {
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v1/collections');
  final out = <CollectionCard>[];
  for (final card in (json['collections'] as List<dynamic>? ?? [])) {
    out.add(_cardFromJson(card as Map<String, dynamic>));
  }
  for (final group in (json['groups'] as List<dynamic>? ?? [])) {
    for (final card in ((group as Map<String, dynamic>)['collections'] as List<dynamic>? ?? [])) {
      out.add(_cardFromJson(card as Map<String, dynamic>));
    }
  }
  return out;
}
