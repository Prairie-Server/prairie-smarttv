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

const _boxSet =
    '"id":"119","library_id":"7","title":"The Lord of the Rings Box Set","overview":"One ring.",'
    '"poster_url":"/p.jpg","poster_thumbhash":"abc","first_year":2001,"last_year":2003,'
    '"movie_count":3,"played_count":1';

String _movie(String id, int year) =>
    '{"content_id":"$id","title":"$id","type":"movie","year":$year,"status":"available","genres":[],"keywords":[]}';

void main() {
  test('box set search asks for the query and reads every field', () async {
    late Uri seen;
    final client = _clientWith((o) {
      seen = o.uri;
      return jsonResponse('{"items":[{$_boxSet},{"id":"","library_id":"7","title":"x"}]}', 200);
    });
    final sets = await searchBoxSets(client, _session, 'lord rings');
    expect(seen.path, '/api/v2/catalog/box-sets');
    expect(seen.queryParameters['q'], 'lord rings');
    expect(seen.queryParameters['limit'], '5');
    final set = sets.single;
    expect(set.id, '119');
    expect(set.libraryId, '7');
    expect(set.title, 'The Lord of the Rings Box Set');
    expect(set.posterThumbhash, 'abc');
    expect(set.movieCount, 3);
    expect(set.playedCount, 1);
  });

  test('a box set lists its movies in the order the server sends', () async {
    late Uri seen;
    final client = _clientWith((o) {
      seen = o.uri;
      return jsonResponse('{$_boxSet,"items":[${_movie('fellowship', 2001)},${_movie('towers', 2002)},${_movie('king', 2003)}]}', 200);
    });
    final detail = await fetchBoxSet(client, _session, id: '119', libraryId: '7');
    expect(seen.path, '/api/v2/catalog/box-sets/119');
    expect(seen.queryParameters['library_id'], '7');
    expect(detail.boxSet.title, 'The Lord of the Rings Box Set');
    expect(detail.items.map((i) => i.contentId), ['fellowship', 'towers', 'king']);
  });

  test("a movie's box set is null when it has none or the server doesn't know", () async {
    var status = 200;
    final client = _clientWith((o) {
      expect(o.uri.path, '/api/v2/catalog/items/m1/box-set');
      return status == 200 ? jsonResponse('{}', 200) : jsonResponse('{"error":"not found"}', status);
    });
    expect(await fetchItemBoxSet(client, _session, 'm1'), isNull);
    status = 404;
    expect(await fetchItemBoxSet(client, _session, 'm1'), isNull);
    status = 500;
    await expectLater(fetchItemBoxSet(client, _session, 'm1'), throwsA(isA<ApiError>()));
  });

  test("a movie's box set comes back with its movies", () async {
    final client = _clientWith((_) => jsonResponse('{"box_set":{$_boxSet,"items":[${_movie('fellowship', 2001)}]}}', 200));
    final detail = await fetchItemBoxSet(client, _session, 'fellowship');
    expect(detail!.boxSet.id, '119');
    expect(detail.items.single.contentId, 'fellowship');
  });

  test('captions follow upstream: progress, then years, then the film count', () {
    BoxSet set({int? first, int? last, int count = 3, int played = 0}) =>
        BoxSet(id: '1', libraryId: '7', title: 'T', firstYear: first, lastYear: last, movieCount: count, playedCount: played);
    expect(set(first: 2001, last: 2003).cardCaption, '2001 – 2003');
    expect(set(first: 2001, last: 2001).cardCaption, '2001');
    expect(set(last: 2003).cardCaption, '2003');
    expect(set().cardCaption, '3 films');
    expect(set(count: 1).cardCaption, '1 film');
    expect(set(first: 2001, last: 2003, played: 2).cardCaption, '2 / 3 watched');
    expect(set(first: 2001, last: 2003, played: 2).heroFacts, ['3 films', '2001 – 2003', '2 of 3 watched']);
    expect(set().heroFacts, ['3 films']);
  });

  test('libraries report whether they gather box sets', () {
    const plain = Library(id: 1, name: 'Movies', type: 'movies');
    const sets = Library(id: 2, name: 'Films', type: 'movies', boxSetsEnabled: true);
    expect(librariesHaveBoxSets([plain]), isFalse);
    expect(librariesHaveBoxSets([plain, sets]), isTrue);
  });

  test("Play picks the first unplayed film, or the first once all are played", () {
    CatalogItem film(String id, {bool played = false, double? position}) => CatalogItem(
      contentId: id,
      type: 'movie',
      title: id,
      positionSeconds: position,
      userState: MediaItemUserState(played: played),
    );
    expect(boxSetNextMovie(const []), isNull);
    expect(boxSetNextMovie([film('a', played: true), film('b'), film('c')])!.contentId, 'b');
    expect(boxSetNextMovie([film('a', played: true), film('b', position: 600), film('c')])!.contentId, 'b');
    expect(boxSetNextMovie([film('a', played: true), film('b', played: true)])!.contentId, 'a');

    const fresh = BoxSet(id: '1', libraryId: '7', title: 'T', movieCount: 3);
    const started = BoxSet(id: '1', libraryId: '7', title: 'T', movieCount: 3, playedCount: 1);
    const done = BoxSet(id: '1', libraryId: '7', title: 'T', movieCount: 3, playedCount: 3);
    expect(boxSetPlayLabel(fresh, film('Alpha')), 'Play Alpha');
    expect(boxSetPlayLabel(fresh, film('Alpha', position: 120)), 'Continue · Alpha');
    expect(boxSetPlayLabel(started, film('Beta')), 'Continue · Beta');
    expect(boxSetPlayLabel(done, film('Alpha', played: true, position: 50)), 'Play Alpha');
  });
}
