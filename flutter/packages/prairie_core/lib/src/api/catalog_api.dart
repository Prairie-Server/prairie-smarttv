import '../models/auth.dart';
import '../models/catalog_item.dart';
import '../models/watch_detail.dart';
import '../player/trickplay.dart';
import 'api_client.dart';

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

CatalogItem catalogItemFromJson(Map<String, dynamic> json) => CatalogItem(
  contentId: json['content_id'] as String,
  type: json['type'] as String,
  title: json['title'] as String,
  year: json['year'] as int?,
  runtime: json['runtime'] as int?,
  genres: (json['genres'] as List<dynamic>?)?.cast<String>(),
  contentRating: json['content_rating'] as String?,
  ratingImdb: (json['rating_imdb'] as num?)?.toDouble(),
  overview: json['overview'] as String?,
  posterUrl: json['poster_url'] as String?,
  posterAvifUrl: json['poster_avif_url'] as String?,
  backdropUrl: json['backdrop_url'] as String?,
  backdropAvifUrl: json['backdrop_avif_url'] as String?,
  logoUrl: json['logo_url'] as String?,
  seriesId: json['series_id'] as String?,
  seriesTitle: json['series_title'] as String?,
  seasonNumber: json['season_number'] as int?,
  episodeNumber: json['episode_number'] as int?,
  positionSeconds: (json['position_seconds'] as num?)?.toDouble(),
  durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
  userState: json['user_state'] != null ? MediaItemUserState.fromJson(json['user_state'] as Map<String, dynamic>) : null,
);

/// Mirrors `CatalogQuery` from src/api/catalog.ts.
class CatalogQuery {
  const CatalogQuery({
    this.libraryId,
    this.type,
    this.q,
    this.source,
    this.collectionId,
    this.offset,
    this.limit,
    this.snapshot,
    this.sort,
    this.order,
  });

  final int? libraryId;
  final String? type;
  final String? q;
  final String? source;
  final String? collectionId;
  final int? offset;
  final int? limit;
  final String? snapshot;
  final String? sort;
  final String? order;

  String _buildPath() {
    final params = <String, String>{};
    if (libraryId != null) params['library_id'] = '$libraryId';
    if (type != null) params['type'] = type!;
    if (q != null) params['q'] = q!;
    if (source != null) params['source'] = source!;
    if (collectionId != null) params['collection_id'] = collectionId!;
    if (offset != null) params['offset'] = '$offset';
    if (limit != null) params['limit'] = '$limit';
    if (snapshot != null) params['snapshot'] = snapshot!;
    if (sort != null) params['sort'] = sort!;
    if (order != null) params['order'] = order!;
    if (params.isEmpty) return '/api/v1/catalog';
    return '/api/v1/catalog?${Uri(queryParameters: params).query}';
  }
}

/// Mirrors `CatalogResponse` from src/api/catalog.ts.
class CatalogResponse {
  const CatalogResponse({this.total, this.hasMore, this.snapshot, required this.items});

  final int? total;
  final bool? hasMore;
  final String? snapshot;
  final List<CatalogItem> items;
}

/// Mirrors `fetchCatalog`. Response caching (`cachedRequest`) isn't ported.
Future<CatalogResponse> fetchCatalog(ApiClient client, PrairieSession session, [CatalogQuery query = const CatalogQuery()]) async {
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), query._buildPath());
  return CatalogResponse(
    total: json['total'] as int?,
    hasMore: json['has_more'] as bool?,
    snapshot: json['snapshot'] as String?,
    items: (json['items'] as List<dynamic>? ?? []).map((j) => catalogItemFromJson(j as Map<String, dynamic>)).toList(),
  );
}

/// Mirrors `CastMember`/`CrewMember` from src/api/catalog.ts.
class CastMember {
  const CastMember({required this.name, this.character, this.order, this.personId, this.photoUrl});
  final String name;
  final String? character;
  final int? order;
  final String? personId;
  final String? photoUrl;

  factory CastMember.fromJson(Map<String, dynamic> json) => CastMember(
    name: json['name'] as String,
    character: json['character'] as String?,
    order: json['order'] as int?,
    personId: json['person_id'] as String?,
    photoUrl: json['photo_url'] as String?,
  );
}

class CrewMember {
  const CrewMember({required this.name, required this.job, this.personId, this.photoUrl});
  final String name;
  final String job;
  final String? personId;
  final String? photoUrl;

  factory CrewMember.fromJson(Map<String, dynamic> json) =>
      CrewMember(name: json['name'] as String, job: json['job'] as String, personId: json['person_id'] as String?, photoUrl: json['photo_url'] as String?);
}

/// Mirrors `ItemVersion`/`ItemAudioTrack`/`ItemSubtitleTrack` from
/// src/api/catalog.ts.
class ItemVersion {
  const ItemVersion({
    required this.fileId,
    this.resolution,
    this.codecVideo,
    this.codecAudio,
    this.hdr,
    this.container,
    this.duration,
    this.trickplay,
  });

  final int fileId;
  final String? resolution;
  final String? codecVideo;
  final String? codecAudio;
  final bool? hdr;
  final String? container;
  final int? duration;
  final TrickplayInfo? trickplay;

  factory ItemVersion.fromJson(Map<String, dynamic> json) => ItemVersion(
    fileId: json['file_id'] as int,
    resolution: json['resolution'] as String?,
    codecVideo: json['codec_video'] as String?,
    codecAudio: json['codec_audio'] as String?,
    hdr: json['hdr'] as bool?,
    container: json['container'] as String?,
    duration: json['duration'] as int?,
    trickplay: json['trickplay'] != null ? TrickplayInfo.fromJson(json['trickplay'] as Map<String, dynamic>) : null,
  );
}

class ItemExtra {
  const ItemExtra({required this.contentId, required this.kind, this.title, this.durationSeconds, this.fileId});
  final String contentId;
  final String kind;
  final String? title;
  final int? durationSeconds;
  final int? fileId;

  factory ItemExtra.fromJson(Map<String, dynamic> json) => ItemExtra(
    contentId: json['content_id'] as String,
    kind: json['kind'] as String,
    title: json['title'] as String?,
    durationSeconds: json['duration_seconds'] as int?,
    fileId: json['file_id'] as int?,
  );
}

/// Mirrors `ItemDetail` (extends `CatalogItem`) from src/api/catalog.ts.
class ItemDetail {
  const ItemDetail({
    required this.item,
    this.tagline,
    this.ratingRtCritic,
    this.ratingRtAudience,
    this.cast = const [],
    this.crew = const [],
    this.studios = const [],
    this.networks = const [],
    this.releaseDate,
    this.firstAirDate,
    this.lastAirDate,
    this.showStatus,
    this.seasonCount,
    this.episodeCount,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.userData,
    this.versions = const [],
    this.extras = const [],
  });

  final CatalogItem item;
  final String? tagline;
  final int? ratingRtCritic;
  final int? ratingRtAudience;
  final List<CastMember> cast;
  final List<CrewMember> crew;
  final List<String> studios;
  final List<String> networks;
  final String? releaseDate;
  final String? firstAirDate;
  final String? lastAirDate;
  final String? showStatus;
  final int? seasonCount;
  final int? episodeCount;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  final WatchUserData? userData;
  final List<ItemVersion> versions;
  final List<ItemExtra> extras;

  factory ItemDetail.fromJson(Map<String, dynamic> json) => ItemDetail(
    item: catalogItemFromJson(json),
    tagline: json['tagline'] as String?,
    ratingRtCritic: (json['rating_rt_critic'] as num?)?.toInt(),
    ratingRtAudience: (json['rating_rt_audience'] as num?)?.toInt(),
    cast: (json['cast'] as List<dynamic>? ?? []).map((j) => CastMember.fromJson(j as Map<String, dynamic>)).toList(),
    crew: (json['crew'] as List<dynamic>? ?? []).map((j) => CrewMember.fromJson(j as Map<String, dynamic>)).toList(),
    studios: (json['studios'] as List<dynamic>?)?.cast<String>() ?? const [],
    networks: (json['networks'] as List<dynamic>?)?.cast<String>() ?? const [],
    releaseDate: json['release_date'] as String?,
    firstAirDate: json['first_air_date'] as String?,
    lastAirDate: json['last_air_date'] as String?,
    showStatus: json['show_status'] as String?,
    seasonCount: json['season_count'] as int?,
    episodeCount: json['episode_count'] as int?,
    seriesId: json['series_id'] as String?,
    seasonNumber: json['season_number'] as int?,
    episodeNumber: json['episode_number'] as int?,
    userData: json['user_data'] != null ? WatchUserData.fromJson(json['user_data'] as Map<String, dynamic>) : null,
    versions: (json['versions'] as List<dynamic>? ?? []).map((j) => ItemVersion.fromJson(j as Map<String, dynamic>)).toList(),
    extras: (json['extras'] as List<dynamic>? ?? []).map((j) => ItemExtra.fromJson(j as Map<String, dynamic>)).toList(),
  );
}

/// Mirrors `fetchItemDetail`. Response caching isn't ported.
Future<ItemDetail> fetchItemDetail(ApiClient client, PrairieSession session, String contentId) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v1/catalog/items/${Uri.encodeComponent(contentId)}',
  );
  return ItemDetail.fromJson(json);
}

/// Mirrors `SeasonSummary` from src/api/catalog.ts.
class SeasonSummary {
  const SeasonSummary({this.contentId, required this.seasonNumber, this.episodeCount, this.title, this.posterUrl});
  final String? contentId;
  final int seasonNumber;
  final int? episodeCount;
  final String? title;
  final String? posterUrl;

  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
    contentId: json['content_id'] as String?,
    seasonNumber: json['season_number'] as int,
    episodeCount: json['episode_count'] as int?,
    title: json['title'] as String?,
    posterUrl: json['poster_url'] as String?,
  );
}

/// Mirrors `EpisodeSummary` from src/api/catalog.ts.
class EpisodeSummary {
  const EpisodeSummary({
    required this.contentId,
    required this.title,
    this.seasonNumber,
    this.episodeNumber,
    this.overview,
    this.posterUrl,
    this.stillUrl,
    this.runtime,
    this.userData,
  });

  final String contentId;
  final String title;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? overview;
  final String? posterUrl;
  final String? stillUrl;
  final int? runtime;
  final WatchUserData? userData;

  factory EpisodeSummary.fromJson(Map<String, dynamic> json) => EpisodeSummary(
    contentId: json['content_id'] as String,
    title: json['title'] as String,
    seasonNumber: json['season_number'] as int?,
    episodeNumber: json['episode_number'] as int?,
    overview: json['overview'] as String?,
    posterUrl: json['poster_url'] as String?,
    stillUrl: json['still_url'] as String?,
    runtime: json['runtime'] as int?,
    userData: json['user_data'] != null ? WatchUserData.fromJson(json['user_data'] as Map<String, dynamic>) : null,
  );
}

/// Mirrors `fetchSeasons`.
Future<List<SeasonSummary>> fetchSeasons(ApiClient client, PrairieSession session, String seriesId) async {
  final data = await client.request<dynamic>(
    _sessionOptions(session),
    '/api/v1/catalog/series/${Uri.encodeComponent(seriesId)}/seasons',
  );
  final list = data is List ? data : (data as Map<String, dynamic>)['seasons'] as List<dynamic>? ?? [];
  return list.map((j) => SeasonSummary.fromJson(j as Map<String, dynamic>)).toList();
}

/// Mirrors `fetchEpisodes`.
Future<List<EpisodeSummary>> fetchEpisodes(
  ApiClient client,
  PrairieSession session,
  String seriesId,
  int seasonNumber,
) async {
  final data = await client.request<dynamic>(
    _sessionOptions(session),
    '/api/v1/catalog/series/${Uri.encodeComponent(seriesId)}/seasons/$seasonNumber/episodes',
  );
  final list = data is List ? data : (data as Map<String, dynamic>)['episodes'] as List<dynamic>? ?? [];
  return list.map((j) => EpisodeSummary.fromJson(j as Map<String, dynamic>)).toList();
}
