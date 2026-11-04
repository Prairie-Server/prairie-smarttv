import 'package:prairie_core/src/api/api_client.dart';
import 'package:prairie_core/src/api/api_error.dart';
import 'package:prairie_core/src/api/catalog_api.dart' show catalogItemFromJson;
import 'package:prairie_core/src/models/auth.dart';
import 'package:prairie_core/src/models/catalog_item.dart';
import 'package:prairie_core/src/models/library.dart';

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

/// A movie box set: the movies one TMDB collection gathers in a library
/// (v2 `CatalogBoxSet`). [title] already reads "Box Set" where TMDB says
/// "Collection".
class BoxSet {
  const BoxSet({
    required this.id,
    required this.libraryId,
    required this.title,
    this.overview,
    this.posterUrl,
    this.posterThumbhash,
    this.backdropUrl,
    this.backdropThumbhash,
    this.firstYear,
    this.lastYear,
    this.movieCount = 0,
    this.playedCount = 0,
  });

  /// The TMDB collection id.
  final String id;

  /// The library whose movies make up the set; reads of the set name it.
  final String libraryId;
  final String title;
  final String? overview;
  final String? posterUrl;
  final String? posterThumbhash;
  final String? backdropUrl;
  final String? backdropThumbhash;
  final int? firstYear;
  final int? lastYear;
  final int movieCount;
  final int playedCount;

  factory BoxSet.fromJson(Map<String, dynamic> json) => BoxSet(
    id: '${json['id']}',
    libraryId: '${json['library_id']}',
    title: json['title'] as String? ?? '',
    overview: json['overview'] as String?,
    posterUrl: json['poster_url'] as String?,
    posterThumbhash: json['poster_thumbhash'] as String?,
    backdropUrl: json['backdrop_url'] as String?,
    backdropThumbhash: json['backdrop_thumbhash'] as String?,
    firstYear: (json['first_year'] as num?)?.toInt(),
    lastYear: (json['last_year'] as num?)?.toInt(),
    movieCount: (json['movie_count'] as num?)?.toInt() ?? 0,
    playedCount: (json['played_count'] as num?)?.toInt() ?? 0,
  );

  /// "2001 – 2011", one year when the set spans one, or null with no year.
  String? get yearsLabel {
    final first = (firstYear ?? 0) > 0 ? firstYear : null;
    final last = (lastYear ?? 0) > 0 ? lastYear : null;
    if (first != null && last != null && first != last) return '$first – $last';
    return (first ?? last)?.toString();
  }

  /// A card's caption: watched progress once started, else the years or the
  /// film count. Mirrors Android's `cardCaption`.
  String get cardCaption =>
      playedCount > 0 ? '$playedCount / $movieCount watched' : yearsLabel ?? boxSetFilmCount(movieCount);

  /// Some of the set's movies are played, but not all.
  bool get isStarted => playedCount > 0 && playedCount < movieCount;

  /// The box set page's facts: film count, years, and watched progress once
  /// started.
  List<String> get heroFacts => [
    boxSetFilmCount(movieCount),
    ?yearsLabel,
    if (playedCount > 0) '$playedCount of $movieCount watched',
  ];
}

/// The movie a box set's Play button starts: the first in release order the
/// profile hasn't played (one in progress isn't played yet), or the first
/// once all are played. Null for an empty set. Android's `boxSetNextMovie`.
CatalogItem? boxSetNextMovie(List<CatalogItem> items) =>
    items.where((item) => item.userState?.played != true).firstOrNull ?? items.firstOrNull;

/// Whether [item] has a position to resume from, as the Play label sees it.
bool boxSetMovieInProgress(CatalogItem item) => item.userState?.played != true && (item.positionSeconds ?? 0) > 0;

/// The Play button's label for [next], the movie [boxSetNextMovie] picked.
String boxSetPlayLabel(BoxSet boxSet, CatalogItem next) =>
    boxSet.isStarted || boxSetMovieInProgress(next) ? 'Continue · ${next.title}' : 'Play ${next.title}';

/// "8 films", or "1 film".
String boxSetFilmCount(int count) => count == 1 ? '1 film' : '$count films';

/// A box set with its movies the viewer can see, in collection (release)
/// order (v2 `CatalogBoxSetDetail`).
class BoxSetDetail {
  const BoxSetDetail({required this.boxSet, required this.items});

  final BoxSet boxSet;
  final List<CatalogItem> items;

  factory BoxSetDetail.fromJson(Map<String, dynamic> json) => BoxSetDetail(
    boxSet: BoxSet.fromJson(json),
    items: [
      for (final item in json['items'] as List<dynamic>? ?? const [])
        catalogItemFromJson(item as Map<String, dynamic>),
    ],
  );
}

/// Whether any library the viewer sees gathers box sets; servers and
/// libraries without them are never asked about box sets.
bool librariesHaveBoxSets(Iterable<Library> libraries) => libraries.any((library) => library.boxSetsEnabled);

/// `GET /api/v2/catalog/box-sets`: box sets matching [query], best first,
/// from libraries that list box sets in search.
Future<List<BoxSet>> searchBoxSets(ApiClient client, PrairieSession session, String query, {int limit = 5}) async {
  final params = Uri(queryParameters: {'q': query, 'limit': '$limit'}).query;
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/catalog/box-sets?$params');
  return [
    for (final item in json['items'] as List<dynamic>? ?? const []) BoxSet.fromJson(item as Map<String, dynamic>),
  ].where((set) => set.id.isNotEmpty && set.title.isNotEmpty).toList();
}

/// `GET /api/v2/catalog/box-sets/{id}?library_id=`: one box set and its
/// movies. 404 when the library turned box sets off or the viewer sees too
/// few of its movies.
Future<BoxSetDetail> fetchBoxSet(ApiClient client, PrairieSession session, {required String id, required String libraryId}) async {
  final params = Uri(queryParameters: {'library_id': libraryId}).query;
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/catalog/box-sets/${Uri.encodeComponent(id)}?$params',
  );
  return BoxSetDetail.fromJson(json);
}

/// `GET /api/v2/catalog/items/{id}/box-set`: the box set a movie's page
/// shows, or null when the movie is in none the viewer sees (or the server
/// doesn't know the movie's box sets).
Future<BoxSetDetail?> fetchItemBoxSet(ApiClient client, PrairieSession session, String contentId) async {
  try {
    final json = await client.request<Map<String, dynamic>>(
      _sessionOptions(session),
      '/api/v2/catalog/items/${Uri.encodeComponent(contentId)}/box-set',
    );
    final boxSet = json['box_set'];
    return boxSet is Map<String, dynamic> ? BoxSetDetail.fromJson(boxSet) : null;
  } on ApiError catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
}
