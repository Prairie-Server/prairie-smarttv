import '../models/auth.dart';
import '../models/catalog_item.dart';
import 'api_client.dart';
import 'api_error.dart';
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

  /// This section with at most [count] cards.
  HomeSection capped(int count) => items.length <= count
      ? this
      : HomeSection(
          id: id,
          sectionType: sectionType,
          title: title,
          featured: featured,
          itemLimit: itemLimit,
          totalCount: totalCount,
          items: items.take(count).toList(),
        );

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

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

/// Most cards a Home row shows. Every row past that opens in full through
/// its Explore all card. Matches Android TV and tvOS.
const homeRowCardCap = 20;

/// Whether [section]'s row ends in an Explore all card: every non-featured
/// row with cards (Home drops titles another row already shows, so even a
/// short row may hide part of its list).
bool sectionOffersExploreAll(HomeSection section) => section.featured != true && section.items.isNotEmpty;

/// The `item_limit` the Home section list carries, given the server's
/// advertised `section_item_limit_max`: [homeRowCardCap], or less when the
/// server allows less. Null (send nothing) when the server advertises none,
/// since an older server rejects the parameter.
int? sectionItemLimitFor(int? sectionItemLimitMax) {
  if (sectionItemLimitMax == null || sectionItemLimitMax <= 0) return null;
  return sectionItemLimitMax < homeRowCardCap ? sectionItemLimitMax : homeRowCardCap;
}

/// `GET /api/v2/home/capabilities` → `section_item_limit_max`, or null when
/// the server has none.
Future<int?> fetchSectionItemLimitMax(ApiClient client, PrairieSession session) async {
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/home/capabilities');
  return (json['section_item_limit_max'] as num?)?.toInt();
}

/// Whether [error] is a server refusing `item_limit` as an unknown query
/// parameter (422 validation_failed, `query.item_limit` unknown_parameter).
bool rejectsItemLimit(Object error) {
  if (error is! ApiError || error.status != 422) return false;
  final body = error.body;
  if (body is! Map) return false;
  final errors = body['errors'];
  if (errors is! List) return false;
  return errors.any((e) => e is Map && e['location'] == 'query.item_limit');
}

/// Mirrors `fetchHomeSections` from src/api/home.ts. Response caching
/// (`cachedRequest`/`CACHE_TTL_MS`) isn't ported yet.
///
/// [itemLimit] (from [sectionItemLimitFor]) caps each row server-side. A
/// server that still rejects it is read again once without it.
Future<List<HomeSection>> fetchHomeSections(ApiClient client, PrairieSession session, {int? itemLimit}) async {
  Map<String, dynamic> json;
  try {
    json = await client.request<Map<String, dynamic>>(
      _sessionOptions(session),
      itemLimit != null ? '/api/v2/home/sections?item_limit=$itemLimit' : '/api/v2/home/sections',
    );
  } catch (e) {
    if (itemLimit == null || !rejectsItemLimit(e)) rethrow;
    json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/home/sections');
  }
  final sections = json['sections'] as List<dynamic>?;
  return sections?.map((s) => HomeSection.fromJson(s as Map<String, dynamic>)).toList() ?? [];
}
