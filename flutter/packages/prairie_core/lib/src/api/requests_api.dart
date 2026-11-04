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
  });

  final bool requestsEnabled;
  final bool allowed;

  /// `available`, `disabled`, `not_configured` or `unsupported`.
  final String state;

  /// The Discover page follows the admin's row layout (`row_order`).
  final bool discoverRowsSupported;

  /// Android's `RequestsFeatureStatus.isEnabled`.
  bool get available => requestsEnabled && allowed && state == 'available';

  factory RequestsStatus.fromJson(Map<String, dynamic> json) => RequestsStatus(
    requestsEnabled: json['requests_enabled'] == true,
    allowed: json['allowed'] == true,
    state: json['state'] as String? ?? '',
    discoverRowsSupported: json['discover_rows_supported'] == true,
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
  );
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

/// Row types that list titles. Brand rows (`studios`, `networks`, `genres`)
/// and types this client doesn't know are left out.
const discoverTitleRowTypes = {'tmdb_chart', 'tmdb_discover', 'tmdb_list', 'mdblist'};

/// `GET /api/v2/requests/discover`: the title rows with titles, in the
/// admin's `row_order`. A server without `row_order` keeps its own order.
Future<List<DiscoverSection>> fetchDiscoverRows(ApiClient client, PrairieSession session) async {
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/requests/discover');
  final sections = [
    for (final item in json['items'] as List<dynamic>? ?? const [])
      if (item is Map<String, dynamic>) DiscoverSection.fromJson(item),
  ].where((section) => section.key.isNotEmpty && section.results.isNotEmpty).toList();
  final order = json['row_order'];
  if (order is! List || order.isEmpty) return sections;
  final byKey = {for (final section in sections) section.key: section};
  return [
    for (final row in order)
      if (row is Map<String, dynamic> && discoverTitleRowTypes.contains(row['type']))
        if (byKey[row['key']] case final section?)
          // The layout's title is the admin's; the section's may be older.
          DiscoverSection(
            key: section.key,
            title: _text(row['title']) ?? section.title,
            results: section.results,
            page: section.page,
            totalPages: section.totalPages,
            nextPage: section.nextPage,
          ),
  ];
}

/// `GET /api/v2/requests/discover/rows/{key}?page=`: a row's See all page.
Future<DiscoverSection> fetchDiscoverRow(ApiClient client, PrairieSession session, String key, {int page = 1}) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/requests/discover/rows/${Uri.encodeComponent(key)}?page=$page',
  );
  return DiscoverSection.fromJson(json);
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

/// `POST /api/v2/requests`: requests [title] (a whole series for a series).
Future<MediaRequest> createRequest(ApiClient client, PrairieSession session, RequestTitle title) async {
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
