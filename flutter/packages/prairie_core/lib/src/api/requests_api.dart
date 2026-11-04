import 'package:prairie_core/src/api/api_client.dart';
import 'package:prairie_core/src/api/api_error.dart';
import 'package:prairie_core/src/models/auth.dart';

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

int? _int(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}');

String? _text(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

/// Whether media requests are on for the viewer (`GET /api/v2/requests/status`,
/// v2 `FeatureStatus`).
class RequestsStatus {
  const RequestsStatus({
    this.requestsEnabled = false,
    this.allowed = false,
    this.state = '',
    this.discoverRowsSupported = false,
    this.seasonRequestsSupported = false,
    this.followSupported = false,
    this.missingSeasonsRequestable = false,
  });

  final bool requestsEnabled;
  final bool allowed;

  /// `available`, `disabled`, `not_configured` or `unsupported`.
  final String state;

  /// The Discover page follows the admin's row layout (`row_order`).
  final bool discoverRowsSupported;

  /// A series request may name its seasons (`seasons` on create).
  final bool seasonRequestsSupported;

  /// The server takes follows of someone else's request
  /// (`PUT`/`DELETE /api/v2/requests/follows/...`).
  final bool followSupported;

  /// A series in the library may still be requested for its missing seasons.
  final bool missingSeasonsRequestable;

  /// Android's `RequestsFeatureStatus.isEnabled`.
  bool get available => requestsEnabled && allowed && state == 'available';

  factory RequestsStatus.fromJson(Map<String, dynamic> json) => RequestsStatus(
    requestsEnabled: json['requests_enabled'] == true,
    allowed: json['allowed'] == true,
    state: json['state'] as String? ?? '',
    discoverRowsSupported: json['discover_rows_supported'] == true,
    seasonRequestsSupported: json['season_requests_supported'] == true,
    followSupported: json['follow_supported'] == true,
    missingSeasonsRequestable: json['missing_seasons_requestable'] == true,
  );
}

/// The problem codes a requests call answers once the admin turns requests
/// off (Android's `CapabilityOff`).
const requestsOffProblemCodes = {'capability_disabled', 'capability_not_configured', 'capability_unsupported'};

/// Whether [error] says requests are off now, so the requests screens close.
/// Other failures are checked against [fetchRequestsStatus].
bool isRequestsOffError(Object error) => error is ApiError && requestsOffProblemCodes.contains(error.code);

/// Servers from before requests answer 404: requests are unsupported there.
Future<RequestsStatus> fetchRequestsStatus(ApiClient client, PrairieSession session) async {
  try {
    return RequestsStatus.fromJson(
      await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/requests/status'),
    );
  } on ApiError catch (e) {
    if (e.status == 404) return const RequestsStatus(state: 'unsupported');
    rethrow;
  }
}

/// The viewer's standing with a title's request (v2 `RequestMediaState`).
class RequestState {
  const RequestState({
    this.requestable = false,
    this.reason,
    this.requestId,
    this.requestedByViewer = false,
    this.following = false,
    this.state,
  });

  /// The viewer may request the title now.
  final bool requestable;

  /// Why it isn't requestable, as a code (`requests_disabled`, ...).
  final String? reason;

  /// The active request, when there is one.
  final String? requestId;
  final bool requestedByViewer;
  final bool following;

  /// `pending`, `approved` or `processing` for an active request.
  final String? state;

  factory RequestState.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const RequestState();
    return RequestState(
      requestable: json['requestable'] == true,
      reason: _text(json['reason']),
      requestId: _text(json['request_id']),
      requestedByViewer: json['requested_by_viewer'] == true,
      following: json['following'] == true,
      state: _text(json['state']),
    );
  }
}

/// A TMDB title in Discover rows, request search, and a request's page (v2
/// `RequestMediaResult`, and the shared fields of `RequestMediaDetail`).
class RequestTitle {
  const RequestTitle({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.year,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.availability = 'missing',
    this.libraryContentId,
    this.request = const RequestState(),
    this.seasons = const [],
  });

  final int tmdbId;

  /// `movie` or `series`.
  final String mediaType;
  final String title;
  final int? year;
  final String? overview;

  /// TMDB image paths; see [tmdbImageUrl].
  final String? posterPath;
  final String? backdropPath;

  /// `missing` or `available` in this server's catalog.
  final String availability;

  /// The library title, once it's in the library.
  final String? libraryContentId;
  final RequestState request;

  /// A series' seasons, on its request page only (empty elsewhere).
  final List<RequestSeason> seasons;

  bool get inLibrary => availability == 'available';

  /// Discover rows and search can hold the same title twice (as a movie
  /// and a series it can't, but rows overlap); this keys a card.
  String get key => '$mediaType:$tmdbId';

  factory RequestTitle.fromJson(Map<String, dynamic> json) => RequestTitle(
    tmdbId: _int(json['tmdb_id']) ?? 0,
    mediaType: json['media_type'] as String? ?? '',
    title: json['title'] as String? ?? '',
    year: _int(json['year']),
    overview: _text(json['overview']),
    posterPath: _text(json['poster_path']),
    backdropPath: _text(json['backdrop_path']),
    availability: json['availability'] as String? ?? 'missing',
    libraryContentId: _text(json['library_content_id']),
    request: RequestState.fromJson(json['request']),
    seasons: [
      for (final season in json['seasons'] is List ? json['seasons'] as List : const [])
        if (season is Map<String, dynamic>) RequestSeason.fromJson(season),
    ]..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber)),
  );

  RequestTitle withRequest(RequestState next) => RequestTitle(
    tmdbId: tmdbId,
    mediaType: mediaType,
    title: title,
    year: year,
    overview: overview,
    posterPath: posterPath,
    backdropPath: backdropPath,
    availability: availability,
    libraryContentId: libraryContentId,
    request: next,
    seasons: seasons,
  );
}

/// One season of a series on its request page (v2 `RequestMediaSeason`).
class RequestSeason {
  const RequestSeason({
    required this.seasonNumber,
    this.episodeCount = 0,
    this.availability = 'missing',
    this.requested = false,
    this.name,
    this.airDate,
  });

  final int seasonNumber;

  /// Episodes TMDB lists, aired or not.
  final int episodeCount;

  /// `missing`, `partial` or `available` (every aired episode is in).
  final String availability;

  /// The title's active request covers this season.
  final bool requested;
  final String? name;

  /// `YYYY-MM-DD`.
  final String? airDate;

  /// A new request can still ask for it: not complete, not already asked
  /// for, and not specials (the server refuses season 0).
  bool get requestable => seasonNumber >= 1 && availability != 'available' && !requested;

  /// Has episodes and first aired on or before [now]'s date.
  bool hasAired(DateTime now) {
    final date = airDate ?? '';
    if (episodeCount <= 0 || date.isEmpty) return false;
    return date.compareTo(now.toIso8601String().substring(0, 10)) <= 0;
  }

  String get label => name ?? (seasonNumber == 0 ? 'Specials' : 'Season $seasonNumber');

  /// "2022 · 9 episodes", or "Not announced". The web's
  /// `formatRequestSeasonMeta`.
  String get metaLabel {
    final date = airDate ?? '';
    final parts = [
      if (date.length >= 4) date.substring(0, 4),
      if (episodeCount > 0) '$episodeCount ${episodeCount == 1 ? 'episode' : 'episodes'}',
    ];
    return parts.isEmpty ? 'Not announced' : parts.join(' · ');
  }

  /// Where a season stands when that matters to the pick: in the library,
  /// requested, part in, or not aired; null for an aired missing season.
  String? statusLabel(DateTime now) {
    if (availability == 'available') return 'In library';
    if (requested) return 'Requested';
    if (availability == 'partial') return 'Partly in library';
    if (hasAired(now)) return null;
    return airDate != null && episodeCount > 0 ? 'Not aired yet' : 'Not announced';
  }

  factory RequestSeason.fromJson(Map<String, dynamic> json) => RequestSeason(
    seasonNumber: _int(json['season_number']) ?? 0,
    episodeCount: _int(json['episode_count']) ?? 0,
    availability: json['availability'] as String? ?? 'missing',
    requested: json['requested'] == true,
    name: _text(json['name']),
    airDate: _text(json['air_date']),
  );
}

/// The seasons a series request asks for unless the viewer changes them:
/// every aired season not yet in the library, as the server picks when
/// given none. The web's `defaultRequestSeasons`.
List<int> defaultRequestSeasons(Iterable<RequestSeason> seasons, DateTime now) => [
  for (final season in seasons)
    if (season.requestable && season.hasAired(now)) season.seasonNumber,
];

/// The `seasons` to send for a pick: null leaves the choice to the server,
/// which it may when the viewer kept the default pick and the server has
/// something to choose (an aired missing season, or a series outside the
/// library, requested whole). Season 0 is never sent; the server refuses
/// it. The web's `RequestSeasonsDialog` submit.
List<int>? requestSeasonsToSend({
  required RequestTitle title,
  required Iterable<int> picked,
  required bool untouched,
  required DateTime now,
}) {
  final defaults = defaultRequestSeasons(title.seasons, now);
  if (untouched && (title.seasons.isEmpty || defaults.isNotEmpty || !title.inLibrary)) return null;
  return [
    for (final number in picked.toSet().toList()..sort())
      if (number >= 1) number,
  ];
}

/// Someone else's open request the viewer could follow (to hear when the
/// title lands) instead of requesting it again. Not for the requester, a
/// title in the library, or one that can be requested. Android's
/// `RequestDetailUiState.canFollow`.
bool canFollowRequest(RequestTitle title, {required bool followSupported}) {
  if (!followSupported) return false;
  final request = title.request;
  if (request.requestable || request.requestedByViewer || request.reason != 'already_requested') return false;
  return !title.inLibrary && request.requestId != null;
}

List<RequestTitle> _titles(Object? json) => [
  for (final item in json is List ? json : const [])
    if (item is Map<String, dynamic>) RequestTitle.fromJson(item),
].where((title) => title.tmdbId > 0 && title.title.isNotEmpty && (title.mediaType == 'movie' || title.mediaType == 'series')).toList();

/// A TMDB image at [width] (`w185`, `w342`, `w780`, ...), or null without a
/// path.
String? tmdbImageUrl(String? path, {String width = 'w342'}) {
  final trimmed = path?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
  return 'https://image.tmdb.org/t/p/$width${trimmed.startsWith('/') ? '' : '/'}$trimmed';
}

/// What a card under Search's "Available to request" may list: titles the
/// library doesn't have yet, which belong under the library results
/// instead. Android's `withoutLibraryTitles`.
List<RequestTitle> withoutLibraryTitles(Iterable<RequestTitle> titles) =>
    titles.where((title) => !title.inLibrary).toList();

/// One Discover row's page of titles (v2 `DiscoverSection`).
class DiscoverSection {
  const DiscoverSection({
    required this.key,
    required this.title,
    required this.results,
    this.page = 1,
    this.totalPages = 1,
    this.nextPage,
  });

  /// The row's stable id; its See all page asks for it by this.
  final String key;
  final String title;
  final List<RequestTitle> results;
  final int page;
  final int totalPages;

  /// The page to ask for next, when the server filled this one from more
  /// than one provider page.
  final int? nextPage;

  /// The page after this one, or null at the end.
  int? get followingPage {
    final next = nextPage ?? page + 1;
    return next > totalPages ? null : next;
  }

  factory DiscoverSection.fromJson(Map<String, dynamic> json) => DiscoverSection(
    key: json['key'] as String? ?? '',
    title: json['title'] as String? ?? '',
    results: _titles(json['results']),
    page: _int(json['page']) ?? 1,
    totalPages: _int(json['total_pages']) ?? 1,
    nextPage: _int(json['next_page']),
  );
}

/// Row types that list titles. Brand rows ([discoverBrandKinds]) and types
/// this client doesn't know are left out.
const discoverTitleRowTypes = {'tmdb_chart', 'tmdb_discover', 'tmdb_list', 'mdblist'};

/// Brand row types: each draws the cards of its brand list
/// (`GET /api/v2/requests/discover/{kind}`).
const discoverBrandKinds = {'studios', 'networks', 'genres'};

/// One row of the Discover page, in the admin's order.
sealed class DiscoverRow {
  const DiscoverRow();

  String get title;

  /// Stable across loads; a See all page returns focus by it.
  String get key;
}

/// A row of titles.
class DiscoverTitleRow extends DiscoverRow {
  const DiscoverTitleRow(this.section);

  final DiscoverSection section;

  @override
  String get title => section.title;

  @override
  String get key => section.key;
}

/// A row of studio, network or genre cards, each opening its browse page.
class DiscoverBrandRow extends DiscoverRow {
  const DiscoverBrandRow({required this.kind, required this.title, required this.brands});

  /// `studios`, `networks` or `genres`.
  final String kind;
  @override
  final String title;
  final List<DiscoverBrand> brands;

  @override
  String get key => kind;
}

/// A studio, network or genre on the Discover page (v2 `DiscoverBrand`).
class DiscoverBrand {
  const DiscoverBrand({
    required this.kind,
    required this.slug,
    required this.displayName,
    this.gradientFrom,
    this.gradientTo,
    this.logoUrl,
    this.seriesSupported = false,
  });

  /// `studios`, `networks` or `genres`: the list it came from.
  final String kind;
  final String slug;
  final String displayName;

  /// `#rrggbb` card colors; see [parseBrandColor].
  final String? gradientFrom;
  final String? gradientTo;
  final String? logoUrl;

  /// A genre that can also be browsed for series.
  final bool seriesSupported;

  /// The media types its browse page offers: a studio's movies, a network's
  /// series, a genre's movies and, when supported, its series.
  List<String> get mediaTypes => switch (kind) {
    'networks' => const ['series'],
    'genres' when seriesSupported => const ['movie', 'series'],
    _ => const ['movie'],
  };

  /// Keys a card and its browse page.
  String get key => '$kind:$slug';

  factory DiscoverBrand.fromJson(String kind, Map<String, dynamic> json) => DiscoverBrand(
    kind: kind,
    slug: json['slug'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    gradientFrom: _text(json['gradient_from']),
    gradientTo: _text(json['gradient_to']),
    logoUrl: _text(json['logo_url']),
    seriesSupported: json['series_supported'] == true,
  );
}

/// A `#rrggbb` (or `rrggbb`) brand color as an opaque ARGB value, or null.
int? parseBrandColor(String? hex) {
  var digits = hex?.trim() ?? '';
  if (digits.startsWith('#')) digits = digits.substring(1);
  if (digits.length != 6) return null;
  final value = int.tryParse(digits, radix: 16);
  return value == null ? null : 0xFF000000 | value;
}

const _brandRowTitles = {'studios': 'Studios', 'networks': 'Networks', 'genres': 'Genres'};

/// `GET /api/v2/requests/discover/{kind}`: the studios, networks or genres a
/// brand row shows.
Future<List<DiscoverBrand>> fetchDiscoverBrands(ApiClient client, PrairieSession session, String kind) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/requests/discover/${Uri.encodeComponent(kind)}',
  );
  return [
    for (final item in json['items'] as List<dynamic>? ?? const [])
      if (item is Map<String, dynamic>) DiscoverBrand.fromJson(kind, item),
  ].where((brand) => brand.slug.isNotEmpty && brand.displayName.isNotEmpty).toList();
}

List<DiscoverSection> _discoverSections(Map<String, dynamic> json) => [
  for (final item in json['items'] as List<dynamic>? ?? const [])
    if (item is Map<String, dynamic>) DiscoverSection.fromJson(item),
].where((section) => section.key.isNotEmpty && section.results.isNotEmpty).toList();

/// The section at [row]'s key under the layout's title (the admin's; the
/// section's may be older), or null when the row has no titles.
DiscoverSection? _sectionForRow(Map<String, DiscoverSection> byKey, Map<String, dynamic> row) {
  final section = byKey[row['key']];
  if (section == null) return null;
  return DiscoverSection(
    key: section.key,
    title: _text(row['title']) ?? section.title,
    results: section.results,
    page: section.page,
    totalPages: section.totalPages,
    nextPage: section.nextPage,
  );
}

/// `GET /api/v2/requests/discover`: the title rows with titles, in the
/// admin's `row_order`. A server without `row_order` keeps its own order.
Future<List<DiscoverSection>> fetchDiscoverRows(ApiClient client, PrairieSession session) async {
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/requests/discover');
  final sections = _discoverSections(json);
  final order = json['row_order'];
  if (order is! List || order.isEmpty) return sections;
  final byKey = {for (final section in sections) section.key: section};
  return [
    for (final row in order)
      if (row is Map<String, dynamic> && discoverTitleRowTypes.contains(row['type']))
        ?_sectionForRow(byKey, row),
  ];
}

/// The whole Discover page in the admin's `row_order`: title rows with
/// titles, and brand rows with their cards (read alongside). A brand list
/// that fails or comes back empty drops its row; the page still shows. A
/// server without `row_order` has title rows only.
Future<List<DiscoverRow>> fetchDiscoverLayout(ApiClient client, PrairieSession session) async {
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/requests/discover');
  final sections = _discoverSections(json);
  final order = json['row_order'];
  if (order is! List || order.isEmpty) return [for (final section in sections) DiscoverTitleRow(section)];
  final byKey = {for (final section in sections) section.key: section};
  final rows = [
    for (final row in order)
      if (row is Map<String, dynamic>) row,
  ];
  // Read each brand list once, all at once.
  final kinds = {
    for (final row in rows)
      if (discoverBrandKinds.contains(row['type'])) row['type'] as String,
  };
  final lists = await Future.wait([
    for (final kind in kinds)
      fetchDiscoverBrands(client, session, kind).catchError((Object _) => const <DiscoverBrand>[]),
  ]);
  final brands = Map.fromIterables(kinds, lists);
  DiscoverRow? layoutRow(Map<String, dynamic> row) {
    final type = row['type'];
    if (discoverTitleRowTypes.contains(type)) {
      final section = _sectionForRow(byKey, row);
      return section == null ? null : DiscoverTitleRow(section);
    }
    final list = brands[type];
    if (type is! String || list == null || list.isEmpty) return null;
    return DiscoverBrandRow(kind: type, title: _text(row['title']) ?? _brandRowTitles[type]!, brands: list);
  }

  return [for (final row in rows) ?layoutRow(row)];
}

/// `GET /api/v2/requests/discover/rows/{key}?page=`: a row's See all page.
Future<DiscoverSection> fetchDiscoverRow(ApiClient client, PrairieSession session, String key, {int page = 1}) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/requests/discover/rows/${Uri.encodeComponent(key)}?page=$page',
  );
  return DiscoverSection.fromJson(json);
}

/// Brand browse orders, as the server names them, with their labels.
const brandBrowseSorts = {'popularity': 'Popular', 'vote_average': 'Top rated', 'release_date': 'Newest'};

/// One page of a studio's, network's or genre's titles (v2
/// `DiscoverBrowsePage`).
class DiscoverBrowsePage {
  const DiscoverBrowsePage({
    required this.results,
    this.displayName = '',
    this.mediaType = 'movie',
    this.sort = 'popularity',
    this.page = 1,
    this.totalPages = 1,
  });

  final List<RequestTitle> results;
  final String displayName;
  final String mediaType;
  final String sort;
  final int page;
  final int totalPages;

  /// The page after this one, or null at the end.
  int? get followingPage => page + 1 > totalPages ? null : page + 1;

  factory DiscoverBrowsePage.fromJson(Map<String, dynamic> json) => DiscoverBrowsePage(
    results: _titles(json['results']),
    displayName: json['display_name'] as String? ?? '',
    mediaType: json['media_type'] as String? ?? 'movie',
    sort: json['sort'] as String? ?? 'popularity',
    page: _int(json['page']) ?? 1,
    totalPages: _int(json['total_pages']) ?? 1,
  );
}

/// `GET /api/v2/requests/discover/browse/{studio|network|genre}/{slug}`: a
/// page of [brand]'s titles in [sort] order. [mediaType] picks a genre's
/// movies or series; a studio is movies and a network series either way.
Future<DiscoverBrowsePage> browseDiscoverBrand(
  ApiClient client,
  PrairieSession session,
  DiscoverBrand brand, {
  String? mediaType,
  String sort = 'popularity',
  int page = 1,
}) async {
  final segment = switch (brand.kind) {
    'studios' => 'studio',
    'networks' => 'network',
    _ => 'genre',
  };
  final params = Uri(
    queryParameters: {
      if (brand.kind == 'genres') 'media_type': mediaType ?? brand.mediaTypes.first,
      'sort': sort,
      'page': '$page',
    },
  ).query;
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/requests/discover/browse/$segment/${Uri.encodeComponent(brand.slug)}?$params',
  );
  return DiscoverBrowsePage.fromJson(json);
}

/// `GET /api/v2/requests/search?q=`: TMDB titles matching [query], in- and
/// out-of-library alike (see [withoutLibraryTitles]).
Future<List<RequestTitle>> searchRequestTitles(ApiClient client, PrairieSession session, String query) async {
  final params = Uri(queryParameters: {'q': query}).query;
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/requests/search?$params');
  return _titles(json['results']);
}

/// `GET /api/v2/requests/detail/{media_type}/{tmdb_id}`: the title with the
/// viewer's current request state.
Future<RequestTitle> fetchRequestTitle(ApiClient client, PrairieSession session, {required String mediaType, required int tmdbId}) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/requests/detail/${Uri.encodeComponent(mediaType)}/$tmdbId',
  );
  return RequestTitle.fromJson(json);
}

/// One of the viewer's requests (v2 `MediaRequest`).
class MediaRequest {
  const MediaRequest({
    required this.id,
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    this.year,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.state = 'pending',
    this.libraryContentId,
  });

  final String id;
  final String mediaType;
  final int tmdbId;
  final String title;
  final int? year;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;

  /// pending, approved, processing, partially_available, available,
  /// declined, cancelled or failed.
  final String state;
  final String? libraryContentId;

  factory MediaRequest.fromJson(Map<String, dynamic> json) => MediaRequest(
    id: '${json['id'] ?? ''}',
    mediaType: json['media_type'] as String? ?? '',
    tmdbId: _int(json['tmdb_id']) ?? 0,
    title: json['title'] as String? ?? '',
    year: _int(json['year']),
    overview: _text(json['overview']),
    posterPath: _text(json['poster_path']),
    backdropPath: _text(json['backdrop_path']),
    state: json['state'] as String? ?? 'pending',
    libraryContentId: _text(json['library_content_id']),
  );

  /// The request as a title card, for opening its page.
  RequestTitle get asTitle => RequestTitle(
    tmdbId: tmdbId,
    mediaType: mediaType,
    title: title,
    year: year,
    overview: overview,
    posterPath: posterPath,
    backdropPath: backdropPath,
    availability: state == 'available' ? 'available' : 'missing',
    libraryContentId: libraryContentId,
    request: RequestState(requestId: id, requestedByViewer: true, following: true, state: state),
  );
}

/// The words a card shows for a request's [state].
String requestStateLabel(String? state) => switch (state) {
  'pending' => 'Pending',
  'approved' => 'Approved',
  'processing' => 'Processing',
  'partially_available' => 'Partly available',
  'available' => 'Available',
  'declined' => 'Declined',
  'cancelled' => 'Cancelled',
  'failed' => 'Failed',
  _ => 'Requested',
};

/// `GET /api/v2/requests/mine`: the viewer's requests, newest first.
Future<List<MediaRequest>> fetchMyRequests(ApiClient client, PrairieSession session, {int limit = 20}) async {
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/requests/mine?limit=$limit');
  return [
    for (final item in json['items'] as List<dynamic>? ?? const [])
      if (item is Map<String, dynamic>) MediaRequest.fromJson(item),
  ].where((request) => request.id.isNotEmpty && request.tmdbId > 0).toList();
}

/// `POST /api/v2/requests`: requests [title]. For a series, [seasons] names
/// the seasons; without it the server picks every aired season not yet
/// complete (the whole series before one has aired).
Future<MediaRequest> createRequest(
  ApiClient client,
  PrairieSession session,
  RequestTitle title, {
  List<int>? seasons,
}) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/requests',
    method: 'POST',
    body: {
      'media_type': title.mediaType,
      'tmdb_id': title.tmdbId,
      'title': title.title,
      'year': ?title.year,
      'poster_path': ?title.posterPath,
      'backdrop_path': ?title.backdropPath,
      'overview': ?title.overview,
      if (title.mediaType == 'series' && seasons != null) 'seasons': seasons,
    },
  );
  return MediaRequest.fromJson(json);
}

/// `POST /api/v2/requests/{id}/cancel`.
Future<void> cancelRequest(ApiClient client, PrairieSession session, String requestId) => client.request<dynamic>(
  _sessionOptions(session),
  '/api/v2/requests/${Uri.encodeComponent(requestId)}/cancel',
  method: 'POST',
);

/// `PUT /api/v2/requests/follows/{media_type}/{tmdb_id}`: tell the viewer
/// when [title] lands. Answers the viewer's new standing with it.
Future<RequestState> followRequestTitle(ApiClient client, PrairieSession session, RequestTitle title) async {
  final json = await client.request<dynamic>(
    _sessionOptions(session),
    '/api/v2/requests/follows/${Uri.encodeComponent(title.mediaType)}/${title.tmdbId}',
    method: 'PUT',
  );
  return RequestState.fromJson(json);
}

/// `DELETE /api/v2/requests/follows/{media_type}/{tmdb_id}`: stop telling the
/// viewer.
Future<void> unfollowRequestTitle(ApiClient client, PrairieSession session, RequestTitle title) =>
    client.request<dynamic>(
      _sessionOptions(session),
      '/api/v2/requests/follows/${Uri.encodeComponent(title.mediaType)}/${title.tmdbId}',
      method: 'DELETE',
    );
