import '../models/auth.dart';
import '../models/catalog_item.dart';
import 'api_client.dart';
import 'catalog_api.dart' show catalogItemFromJson;

/// Mirrors `HomeSection` from src/api/home.ts.
class HomeSection {
  const HomeSection({
    required this.id,
    required this.sectionType,
    required this.title,
    this.featured,
    this.itemLimit,
    this.totalCount,
    required this.items,
  });

  final String id;
  final String sectionType;
  final String title;
  final bool? featured;
  final int? itemLimit;
  final int? totalCount;
  final List<CatalogItem> items;

  factory HomeSection.fromJson(Map<String, dynamic> json) => HomeSection(
    id: json['id'] as String,
    sectionType: json['section_type'] as String,
    title: json['title'] as String,
    featured: json['featured'] as bool?,
    itemLimit: json['item_limit'] as int?,
    totalCount: json['total_count'] as int?,
    items: (json['items'] as List<dynamic>? ?? [])
        .map((j) => catalogItemFromJson(j as Map<String, dynamic>))
        .toList(),
  );
}

/// Mirrors `fetchHomeSections` from src/api/home.ts. Response caching
/// (`cachedRequest`/`CACHE_TTL_MS`) isn't ported yet.
Future<List<HomeSection>> fetchHomeSections(ApiClient client, PrairieSession session) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(
      serverUrl: session.serverUrl,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      profileId: session.profileId,
      profileToken: session.profileToken,
    ),
    '/api/v1/home/sections',
  );
  final sections = json['sections'] as List<dynamic>?;
  return sections?.map((s) => HomeSection.fromJson(s as Map<String, dynamic>)).toList() ?? [];
}
