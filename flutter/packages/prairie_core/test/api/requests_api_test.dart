import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import '../api/fake_http_adapter.dart';

const _server = 'https://prairie.example.com';
const _session = PrairieSession(serverUrl: _server, accessToken: 'a', username: 'u', profileId: 'p1');

ApiClient _clientWith(ResponseBody Function(RequestOptions) handler) {
  final dio = Dio()..httpClientAdapter = FakeHttpAdapter(handler);
  return ApiClient(dio: dio);
}

String _title(int id, {String type = 'movie', String availability = 'missing'}) =>
    '{"tmdb_id":$id,"media_type":"$type","title":"T$id","year":2020,"poster_path":"/p$id.jpg",'
    '"availability":"$availability","in_watchlist":false,'
    '"request":{"requestable":true,"following":false,"requested_by_viewer":false}}';

String _section(String key, String title, List<int> ids, {int page = 1, int totalPages = 3, int? nextPage}) =>
    '{"key":"$key","title":"$title","page":$page,"total_pages":$totalPages,"total_results":60,'
    '${nextPage == null ? '' : '"next_page":$nextPage,'}'
    '"results":[${ids.map(_title).join(',')}]}';

void main() {
  test('requests are available only when on, allowed and available', () async {
    var body = '{"requests_enabled":true,"allowed":true,"state":"available","discover_rows_supported":true}';
    var status = 200;
    final client = _clientWith((o) {
      expect(o.uri.path, '/api/v2/requests/status');
      return jsonResponse(body, status);
    });
    final on = await fetchRequestsStatus(client, _session);
    expect(on.available, isTrue);
    expect(on.discoverRowsSupported, isTrue);
    body = '{"requests_enabled":false,"allowed":true,"state":"available"}';
    expect((await fetchRequestsStatus(client, _session)).available, isFalse);
    body = '{"requests_enabled":true,"allowed":false,"state":"available"}';
    expect((await fetchRequestsStatus(client, _session)).available, isFalse);
    body = '{"requests_enabled":true,"allowed":true,"state":"not_configured"}';
    expect((await fetchRequestsStatus(client, _session)).available, isFalse);
    body = '{"error":"not found"}';
    status = 404;
    expect((await fetchRequestsStatus(client, _session)).available, isFalse);
  });

  test('a capability problem reads as requests turned off', () {
    expect(isRequestsOffError(ApiError('Capability disabled', 409, 'capability_disabled')), isTrue);
    expect(isRequestsOffError(ApiError('x', 409, 'capability_not_configured')), isTrue);
    expect(isRequestsOffError(ApiError('Conflict', 409, 'already_requested')), isFalse);
    expect(isRequestsOffError(StateError('x')), isFalse);
  });

  test('discover rows follow row_order, skipping brand rows, unknown types and empty rows', () async {
    final client = _clientWith(
      (_) => jsonResponse(
        '{"items":[${_section('trending_movies', 'Trending Movies', [1, 2])},'
        '${_section('popular_series', 'Popular Series', [3])},'
        '${_section('row_empty', 'Empty', [])},'
        '${_section('a1b2', 'Old name', [4])}],'
        '"row_order":['
        '{"key":"a1b2","title":"Staff Picks","type":"tmdb_list"},'
        '{"key":"studios","title":"Studios","type":"studios"},'
        '{"key":"trending_movies","title":"Trending Movies","type":"tmdb_chart"},'
        '{"key":"row_empty","title":"Empty","type":"tmdb_discover"},'
        '{"key":"popular_series","title":"Popular Series","type":"future_kind"}]}',
        200,
      ),
    );
    final rows = await fetchDiscoverRows(client, _session);
    expect(rows.map((r) => r.key), ['a1b2', 'trending_movies']);
    expect(rows.first.title, 'Staff Picks');
    expect(rows.last.results.map((t) => t.tmdbId), [1, 2]);
  });

  test('a server without row_order keeps its own row order', () async {
    final client = _clientWith(
      (_) => jsonResponse('{"items":[${_section('b', 'B', [1])},${_section('a', 'A', [2])}],"row_order":[]}', 200),
    );
    expect((await fetchDiscoverRows(client, _session)).map((r) => r.key), ['b', 'a']);
  });

  test("a row's See all page asks for the row by key and pages on", () async {
    late Uri seen;
    final client = _clientWith((o) {
      seen = o.uri;
      return jsonResponse(_section('staff picks', 'Staff Picks', [5, 6], page: 2, totalPages: 3, nextPage: 4), 200);
    });
    final page = await fetchDiscoverRow(client, _session, 'staff picks', page: 2);
    expect(seen.path, '/api/v2/requests/discover/rows/staff%20picks');
    expect(seen.queryParameters['page'], '2');
    expect(page.results, hasLength(2));
    expect(page.followingPage, isNull);
    expect(DiscoverSection(key: 'k', title: 't', results: const [], page: 1, totalPages: 3).followingPage, 2);
  });

  test('search lists only titles the library lacks under Available to request', () async {
    late Uri seen;
    final client = _clientWith((o) {
      seen = o.uri;
      return jsonResponse(
        '{"page":1,"total_pages":1,"total_results":3,"results":['
        '${_title(1)},${_title(2, availability: 'available')},${_title(3, type: 'series')},'
        '{"tmdb_id":0,"media_type":"movie","title":"bad"},{"tmdb_id":9,"media_type":"person","title":"Someone"}]}',
        200,
      );
    });
    final results = await searchRequestTitles(client, _session, 'dune part');
    expect(seen.path, '/api/v2/requests/search');
    expect(seen.queryParameters['q'], 'dune part');
    expect(results.map((t) => t.tmdbId), [1, 2, 3]);
    expect(withoutLibraryTitles(results).map((t) => t.tmdbId), [1, 3]);
  });

  test('a request sends the title and its artwork paths', () async {
    late RequestOptions seen;
    final client = _clientWith((o) {
      seen = o;
      return jsonResponse(
        '{"id":"r1","media_type":"movie","tmdb_id":7,"title":"T7","state":"pending","status":"pending","outcome":"active"}',
        201,
      );
    });
    const title = RequestTitle(tmdbId: 7, mediaType: 'movie', title: 'T7', posterPath: '/p.jpg');
    final request = await createRequest(client, _session, title);
    expect(seen.method, 'POST');
    expect(seen.uri.path, '/api/v2/requests');
    expect(seen.data, {'media_type': 'movie', 'tmdb_id': 7, 'title': 'T7', 'poster_path': '/p.jpg'});
    expect(request.id, 'r1');
    expect(request.asTitle.request.requestedByViewer, isTrue);
  });

  test('cancel posts to the request', () async {
    late RequestOptions seen;
    final client = _clientWith((o) {
      seen = o;
      return jsonResponse('{"id":"r1"}', 200);
    });
    await cancelRequest(client, _session, 'r1');
    expect(seen.method, 'POST');
    expect(seen.uri.path, '/api/v2/requests/r1/cancel');
  });

  test('my requests and a title page parse their states', () async {
    final client = _clientWith((o) {
      if (o.uri.path == '/api/v2/requests/mine') {
        return jsonResponse(
          '{"items":[{"id":"r1","media_type":"series","tmdb_id":3,"title":"Show","state":"available",'
          '"library_content_id":"c3"},{"id":"","tmdb_id":1,"title":"x"}]}',
          200,
        );
      }
      expect(o.uri.path, '/api/v2/requests/detail/series/3');
      return jsonResponse(
        '{"tmdb_id":3,"media_type":"series","title":"Show","availability":"missing","in_watchlist":false,'
        '"request":{"requestable":false,"reason":"already_requested","request_id":"r1","requested_by_viewer":true,'
        '"following":true,"state":"pending"}}',
        200,
      );
    });
    final mine = await fetchMyRequests(client, _session);
    expect(mine.single.state, 'available');
    expect(mine.single.asTitle.inLibrary, isTrue);
    expect(requestStateLabel(mine.single.state), 'Available');
    final title = await fetchRequestTitle(client, _session, mediaType: 'series', tmdbId: 3);
    expect(title.request.requestable, isFalse);
    expect(title.request.requestId, 'r1');
    expect(title.request.state, 'pending');
  });

  test('TMDB images are sized on the TMDB host', () {
    expect(tmdbImageUrl('/abc.jpg'), 'https://image.tmdb.org/t/p/w342/abc.jpg');
    expect(tmdbImageUrl('abc.jpg', width: 'w780'), 'https://image.tmdb.org/t/p/w780/abc.jpg');
    expect(tmdbImageUrl(null), isNull);
    expect(tmdbImageUrl('  '), isNull);
  });

  test('status reads the season, follow and missing-season flags', () async {
    var body =
        '{"requests_enabled":true,"allowed":true,"state":"available","season_requests_supported":true,'
        '"follow_supported":true,"missing_seasons_requestable":true}';
    final client = _clientWith((_) => jsonResponse(body, 200));
    final current = await fetchRequestsStatus(client, _session);
    expect(current.seasonRequestsSupported, isTrue);
    expect(current.followSupported, isTrue);
    expect(current.missingSeasonsRequestable, isTrue);
    body = '{"requests_enabled":true,"allowed":true,"state":"available"}';
    final older = await fetchRequestsStatus(client, _session);
    expect(older.seasonRequestsSupported, isFalse);
    expect(older.followSupported, isFalse);
    expect(older.missingSeasonsRequestable, isFalse);
  });

  test("a series page lists its seasons in order and what each can be", () async {
    final client = _clientWith(
      (_) => jsonResponse(
        '{"tmdb_id":1399,"media_type":"series","title":"Show","availability":"missing",'
        '"request":{"requestable":true},"seasons":['
        '{"season_number":2,"episode_count":10,"availability":"partial","requested":false,"air_date":"2012-04-01"},'
        '{"season_number":0,"episode_count":3,"availability":"missing","requested":false,"name":"Specials"},'
        '{"season_number":1,"episode_count":1,"availability":"available","requested":false,"air_date":"2011-04-17"},'
        '{"season_number":3,"episode_count":0,"availability":"missing","requested":false}]}',
        200,
      ),
    );
    final title = await fetchRequestTitle(client, _session, mediaType: 'series', tmdbId: 1399);
    final now = DateTime(2026, 11, 3);
    expect(title.seasons.map((s) => s.seasonNumber), [0, 1, 2, 3]);
    expect(title.seasons.map((s) => s.requestable), [false, false, true, true]);
    expect(title.seasons[1].metaLabel, '2011 · 1 episode');
    expect(title.seasons[3].metaLabel, 'Not announced');
    expect(title.seasons[3].label, 'Season 3');
    expect(title.seasons[1].statusLabel(now), 'In library');
    expect(title.seasons[2].statusLabel(now), 'Partly in library');
    expect(title.seasons[3].statusLabel(now), 'Not announced');
    expect(defaultRequestSeasons(title.seasons, now), [2]);
    expect(title.withRequest(const RequestState()).seasons, hasLength(4));
  });

  test('an untouched season pick leaves the choice to the server when it has one', () {
    final now = DateTime(2026, 11, 3);
    const aired = RequestSeason(seasonNumber: 1, episodeCount: 8, airDate: '2020-01-01');
    const upcoming = RequestSeason(seasonNumber: 2, episodeCount: 8, airDate: '2027-01-01');
    const missing = RequestTitle(tmdbId: 1, mediaType: 'series', title: 'S', seasons: [aired, upcoming]);
    expect(requestSeasonsToSend(title: missing, picked: const [1], untouched: true, now: now), isNull);
    expect(requestSeasonsToSend(title: missing, picked: const [2, 1, 2], untouched: false, now: now), [1, 2]);
    // In the library with only an upcoming season left, the viewer has to name it.
    const inLibrary = RequestTitle(
      tmdbId: 1,
      mediaType: 'series',
      title: 'S',
      availability: 'available',
      seasons: [RequestSeason(seasonNumber: 1, episodeCount: 8, airDate: '2020-01-01', availability: 'available'), upcoming],
    );
    expect(requestSeasonsToSend(title: inLibrary, picked: const [], untouched: true, now: now), isEmpty);
    expect(requestSeasonsToSend(title: inLibrary, picked: const [0, 2], untouched: false, now: now), [2]);
  });

  test('a series request names its picked seasons; a movie never does', () async {
    final sent = <Object?>[];
    final client = _clientWith((o) {
      sent.add(o.data);
      return jsonResponse('{"id":"r1","media_type":"series","tmdb_id":5,"title":"S","state":"pending"}', 201);
    });
    const series = RequestTitle(tmdbId: 5, mediaType: 'series', title: 'S');
    await createRequest(client, _session, series, seasons: const [2, 3]);
    await createRequest(client, _session, series);
    await createRequest(client, _session, const RequestTitle(tmdbId: 6, mediaType: 'movie', title: 'M'), seasons: const [1]);
    expect((sent[0]! as Map)['seasons'], [2, 3]);
    expect((sent[1]! as Map).containsKey('seasons'), isFalse);
    expect((sent[2]! as Map).containsKey('seasons'), isFalse);
  });

  test("following someone else's request puts and deletes the follow", () async {
    final seen = <String>[];
    final client = _clientWith((o) {
      seen.add('${o.method} ${o.uri.path}');
      return o.method == 'PUT'
          ? jsonResponse('{"requestable":false,"reason":"already_requested","request_id":"r9","following":true}', 200)
          : ResponseBody.fromString('', 204);
    });
    const title = RequestTitle(tmdbId: 1399, mediaType: 'series', title: 'S');
    final state = await followRequestTitle(client, _session, title);
    expect(state.following, isTrue);
    await unfollowRequestTitle(client, _session, title);
    expect(seen, ['PUT /api/v2/requests/follows/series/1399', 'DELETE /api/v2/requests/follows/series/1399']);
  });

  test("only someone else's open request can be followed", () {
    RequestTitle title({
      bool requestable = false,
      bool mine = false,
      String? reason = 'already_requested',
      String availability = 'missing',
    }) => RequestTitle(
      tmdbId: 1,
      mediaType: 'movie',
      title: 'M',
      availability: availability,
      request: RequestState(requestable: requestable, requestedByViewer: mine, reason: reason, requestId: 'r1', state: 'pending'),
    );
    expect(canFollowRequest(title(), followSupported: true), isTrue);
    expect(canFollowRequest(title(), followSupported: false), isFalse);
    expect(canFollowRequest(title(mine: true), followSupported: true), isFalse);
    expect(canFollowRequest(title(requestable: true), followSupported: true), isFalse);
    expect(canFollowRequest(title(reason: 'requests_disabled'), followSupported: true), isFalse);
    expect(canFollowRequest(title(availability: 'available'), followSupported: true), isFalse);
  });
}
