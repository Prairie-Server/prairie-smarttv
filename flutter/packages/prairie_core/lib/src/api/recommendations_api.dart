import '../models/auth.dart';
import '../models/catalog_item.dart';
import 'api_client.dart';
import 'catalog_api.dart' show catalogItemFromJson;

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

List<CatalogItem> _cards(Object? items) => (items as List<dynamic>? ?? [])
    .map((j) => catalogItemFromJson(j as Map<String, dynamic>))
    .where((c) => c.contentId.isNotEmpty)
    .toList();

/// Mirrors `SimilarItemsResult` from src/api/recommendations.ts. `refs`
/// (raw media_item_id/score/reason, for servers that don't hydrate cards)
/// isn't ported — only the ready-to-render `cards` path is used today.
class SimilarItemsResult {
  const SimilarItemsResult({required this.cards});
  final List<CatalogItem> cards;
}

/// Mirrors `fetchSimilarItems`. Response caching isn't ported.
Future<SimilarItemsResult> fetchSimilarItems(ApiClient client, PrairieSession session, String contentId) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/recommendations/similar/${Uri.encodeComponent(contentId)}',
  );
  return SimilarItemsResult(cards: _cards(json['items'] ?? json['cards']));
}

/// One Discover row (v2 `RecommendationRow`). [kind] is the server's
/// section kind (`for-you-main`, `cluster`, `similar-users`, `popular`,
/// `recently-added`, `top-rated`, `genre`), empty for rows it can't name.
class RecommendationRow {
  const RecommendationRow({required this.title, this.kind = '', required this.items});

  final String title;
  final String kind;
  final List<CatalogItem> items;

  factory RecommendationRow.fromJson(Map<String, dynamic> json) => RecommendationRow(
    title: json['title'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    items: _cards(json['items']),
  );

  /// Built from the profile's own history or favourites, as opposed to the
  /// cold-start popular / top-rated / genre sampler rows every profile gets.
  bool get personalized => const {'for-you-main', 'cluster', 'similar-users'}.contains(kind);
}

/// Kinds the default Home page already shows as rails (Recommended for You,
/// Recently Added, Top Rated — see the server's `DefaultHomeSections`), so
/// the For You tab leaves them out.
const homeDuplicateRowKinds = {'for-you-main', 'recently-added', 'top-rated'};

/// `GET /api/v2/recommendations/discover`: the acting profile's rows, with
/// upcoming airings blended in server-side. Rows without cards are dropped.
Future<List<RecommendationRow>> fetchDiscover(ApiClient client, PrairieSession session) async {
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/recommendations/discover');
  return [
    for (final row in (json['items'] as List<dynamic>? ?? []))
      RecommendationRow.fromJson(row as Map<String, dynamic>),
  ].where((r) => r.items.isNotEmpty).toList();
}

class TasteSeedPage {
  const TasteSeedPage({required this.items, this.nextCursor});
  final List<CatalogItem> items;

  /// Null on the last page.
  final String? nextCursor;
}

/// `GET /api/v2/recommendations/taste-seed/items`: a page of picker cards.
/// Titles the profile already favourited carry `user_state.is_favorite`.
Future<TasteSeedPage> fetchTasteSeedItems(ApiClient client, PrairieSession session, {String? cursor, int limit = 30}) async {
  final query = Uri(queryParameters: {'limit': '$limit', 'cursor': ?cursor}).query;
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/recommendations/taste-seed/items?$query',
  );
  final page = json['page'] as Map<String, dynamic>?;
  final next = page?['has_more'] == true ? page!['next_cursor'] as String? : null;
  return TasteSeedPage(items: _cards(json['items']), nextCursor: next == null || next.isEmpty ? null : next);
}

/// `POST /api/v2/recommendations/taste-seed`: favourites [itemIds] and queues
/// one taste-profile refresh.
Future<void> submitTasteSeed(ApiClient client, PrairieSession session, List<String> itemIds) async {
  await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/recommendations/taste-seed',
    method: 'POST',
    body: {'item_ids': itemIds},
  );
}
