import '../models/auth.dart';
import '../models/catalog_item.dart';
import 'api_client.dart';
import 'catalog_api.dart' show catalogItemFromJson;

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
    ApiClientOptions(
      serverUrl: session.serverUrl,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      profileId: session.profileId,
      profileToken: session.profileToken,
    ),
    '/api/v1/recommendations/similar/${Uri.encodeComponent(contentId)}',
  );
  final cards = (json['cards'] as List<dynamic>? ?? [])
      .map((j) => catalogItemFromJson(j as Map<String, dynamic>))
      .where((c) => c.contentId.isNotEmpty)
      .toList();
  return SimilarItemsResult(cards: cards);
}
