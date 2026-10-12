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
  creatorProfileId: json['creator_profile_id'] as String?,
  collectionType: json['collection_type'] as String?,
  contains: json['contains'] as bool?,
);

/// PATCH/DELETE on a personal collection require `If-Match`.
// ponytail: `*` is last-writer-wins; send getCollection's ETag if the TV ever
// edits fields another device may be changing at the same time.
const _anyRevision = {'If-Match': '*'};

/// Mirrors `fetchLibraryCollections` from src/api/collections.ts.
Future<List<CollectionCard>> fetchLibraryCollections(
  ApiClient client,
  PrairieSession session,
  int libraryId,
) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/library/$libraryId/collections',
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

/// Mirrors `fetchPersonalCollections` from src/api/collections.ts. With
/// [containsItem] (a content id), each own manual collection carries
/// [CollectionCard.contains]; only send it when
/// [CollectionCapabilities.containsItem] is true.
Future<List<CollectionCard>> fetchPersonalCollections(
  ApiClient client,
  PrairieSession session, {
  String? containsItem,
}) async {
  final query = containsItem == null ? '' : '?contains_item=${Uri.encodeQueryComponent(containsItem)}';
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/collections$query');
  final out = <CollectionCard>[];
  // v2 returns personal collections in `items` and grouped collections in
  // `groups[*].collections`. Keep the flattened card contract used by the TV UI.
  for (final card in (json['items'] as List<dynamic>? ?? [])) {
    out.add(_cardFromJson(card as Map<String, dynamic>));
  }
  // `items` is the complete personal collection list. `groups` is
  // presentation metadata and repeats grouped collections, so do not flatten it
  // into the card list or grouped collections appear twice.
  return out;
}

/// `getCollectionCapabilities`: what the acting profile may do with personal
/// collections.
Future<CollectionCapabilities> fetchCollectionCapabilities(ApiClient client, PrairieSession session) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/collections/capabilities',
  );
  return CollectionCapabilities.fromJson(json);
}

/// `getCollection`: one personal collection, for its owner and type.
Future<CollectionCard> fetchPersonalCollection(ApiClient client, PrairieSession session, String id) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/collections/${Uri.encodeComponent(id)}',
  );
  return _cardFromJson(json);
}

/// Trims [name] and rejects an empty one before any request is sent (the
/// server requires `minLength: 1`).
String _collectionName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
  return trimmed;
}

/// `createCollection`: a new manual collection named [name].
Future<CollectionCard> createCollection(ApiClient client, PrairieSession session, String name) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/collections',
    method: 'POST',
    body: {'name': _collectionName(name), 'collection_type': 'manual'},
  );
  return _cardFromJson(json);
}

/// `updateCollection`, renaming only.
Future<void> renameCollection(ApiClient client, PrairieSession session, String id, String name) async {
  await client.request<Object?>(
    _sessionOptions(session),
    '/api/v2/collections/${Uri.encodeComponent(id)}',
    method: 'PATCH',
    body: {'name': _collectionName(name)},
    headers: _anyRevision,
  );
}

/// `deleteCollection`.
Future<void> deleteCollection(ApiClient client, PrairieSession session, String id) async {
  await client.request<Object?>(
    _sessionOptions(session),
    '/api/v2/collections/${Uri.encodeComponent(id)}',
    method: 'DELETE',
    headers: _anyRevision,
  );
}

/// `addCollectionItem`: puts [contentId] first, like the web's Add to
/// collection dialog.
Future<void> addCollectionItem(ApiClient client, PrairieSession session, String id, String contentId) async {
  await client.request<Object?>(
    _sessionOptions(session),
    '/api/v2/collections/${Uri.encodeComponent(id)}/items/${Uri.encodeComponent(contentId)}',
    method: 'PUT',
    body: {'position': 0},
  );
}

/// `removeCollectionItem`.
Future<void> removeCollectionItem(ApiClient client, PrairieSession session, String id, String contentId) async {
  await client.request<Object?>(
    _sessionOptions(session),
    '/api/v2/collections/${Uri.encodeComponent(id)}/items/${Uri.encodeComponent(contentId)}',
    method: 'DELETE',
  );
}
