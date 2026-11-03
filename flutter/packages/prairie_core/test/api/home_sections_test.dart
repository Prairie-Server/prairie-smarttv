import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

const _server = 'https://prairie.example.com';
const _session = PrairieSession(serverUrl: _server, accessToken: 'a', username: 'u', profileId: 'p1');

ApiClient _clientWith(ResponseBody Function(RequestOptions) handler) {
  final dio = Dio()..httpClientAdapter = FakeHttpAdapter(handler);
  return ApiClient(dio: dio);
}

String _card(String id) => '{"content_id":"$id","title":"$id","type":"movie"}';

String _sections(int cards) =>
    '{"sections":[{"id":"s1","section_type":"recently_added","title":"New","items":[${List.generate(cards, (i) => _card('c$i')).join(',')}]}]}';

const _unknownItemLimit =
    '{"type":"https://prairie.example.com/problems/validation_failed","title":"Validation failed","status":422,'
    '"errors":[{"location":"query.item_limit","code":"unknown_parameter"}]}';

void main() {
  group('sectionItemLimitFor', () {
    test('asks for 20 cards when the server allows at least that many', () {
      expect(sectionItemLimitFor(100), 20);
      expect(sectionItemLimitFor(20), 20);
    });

    test('asks for no more than the server allows', () {
      expect(sectionItemLimitFor(12), 12);
    });

    test('sends nothing when the server advertises no maximum', () {
      expect(sectionItemLimitFor(null), isNull);
      expect(sectionItemLimitFor(0), isNull);
    });
  });

  test('reads section_item_limit_max from the Home capabilities', () async {
    final client = _clientWith((o) {
      expect(o.uri.path, '/api/v2/home/capabilities');
      return jsonResponse('{"revision":"r","state":"available","allowed":true,"section_item_limit_max":100}', 200);
    });
    expect(await fetchSectionItemLimitMax(client, _session), 100);
  });

  test('an older server without the field reads as no maximum', () async {
    final client = _clientWith((_) => jsonResponse('{"revision":"r","state":"available","allowed":true}', 200));
    expect(await fetchSectionItemLimitMax(client, _session), isNull);
  });

  test('sends item_limit on the Home section list when given one', () async {
    final limits = <String?>[];
    final client = _clientWith((o) {
      limits.add(o.uri.queryParameters['item_limit']);
      return jsonResponse(_sections(3), 200);
    });
    await fetchHomeSections(client, _session, itemLimit: 20);
    await fetchHomeSections(client, _session);
    expect(limits, ['20', null]);
  });

  test('reads again without item_limit when the server rejects it', () async {
    final limits = <String?>[];
    final client = _clientWith((o) {
      final limit = o.uri.queryParameters['item_limit'];
      limits.add(limit);
      return limit != null ? jsonResponse(_unknownItemLimit, 422) : jsonResponse(_sections(2), 200);
    });
    final sections = await fetchHomeSections(client, _session, itemLimit: 20);
    expect(limits, ['20', null]);
    expect(sections.single.items, hasLength(2));
  });

  test('other errors are not retried', () async {
    var calls = 0;
    final client = _clientWith((_) {
      calls++;
      return jsonResponse('{"title":"Server error","status":500}', 500);
    });
    await expectLater(fetchHomeSections(client, _session, itemLimit: 20), throwsA(isA<ApiError>()));
    expect(calls, 1);
  });

  test('a row shows at most 20 cards and ends in Explore all', () async {
    final client = _clientWith((_) => jsonResponse(_sections(35), 200));
    final section = (await fetchHomeSections(client, _session)).single;
    final capped = section.capped(homeRowCardCap);
    expect(capped.items, hasLength(20));
    expect(capped.items.last.contentId, 'c19');
    expect(capped.id, section.id);
    expect(sectionOffersExploreAll(capped), isTrue);
  });

  test('featured and empty rows get no Explore all card', () {
    const featured = HomeSection(
      id: 'f',
      sectionType: 'featured',
      title: 'Featured',
      featured: true,
      items: [CatalogItem(contentId: 'a', type: 'movie', title: 'a')],
    );
    const empty = HomeSection(id: 'e', sectionType: 'recently_added', title: 'New', items: []);
    expect(sectionOffersExploreAll(featured), isFalse);
    expect(sectionOffersExploreAll(empty), isFalse);
  });

  group('fetchCatalogSourcePage', () {
    test("pages a Home row's full list through source=section", () async {
      final seen = <Uri>[];
      final client = _clientWith((o) {
        seen.add(o.uri);
        return o.uri.queryParameters['cursor'] == null
            ? jsonResponse('{"items":[${_card('a')}],"page":{"has_more":true,"next_cursor":"c2"}}', 200)
            : jsonResponse('{"items":[${_card('b')}],"page":{"has_more":false}}', 200);
      });
      final first = await fetchCatalogSourcePage(client, _session, source: 'section', scope: 'home', sectionId: 's1');
      expect(first.items.single.contentId, 'a');
      expect(first.nextCursor, 'c2');
      expect(seen.first.path, '/api/v2/catalog');
      expect(seen.first.queryParameters, {'source': 'section', 'scope': 'home', 'section_id': 's1', 'limit': '60'});

      final second = await fetchCatalogSourcePage(
        client,
        _session,
        source: 'section',
        scope: 'home',
        sectionId: 's1',
        cursor: first.nextCursor,
      );
      expect(second.items.single.contentId, 'b');
      expect(second.nextCursor, isNull);
      expect(seen.last.queryParameters['cursor'], 'c2');
    });

    test('a row that is gone answers a 404 ApiError', () async {
      final client = _clientWith((_) => jsonResponse('{"status":404,"title":"Not Found"}', 404));
      await expectLater(
        fetchCatalogSourcePage(client, _session, source: 'section', scope: 'home', sectionId: 'gone'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 404)),
      );
    });

    test('history needs no scope or section', () async {
      late Uri seen;
      final client = _clientWith((o) {
        seen = o.uri;
        return jsonResponse('{"items":[],"page":{"has_more":false}}', 200);
      });
      await fetchCatalogSourcePage(client, _session, source: 'history');
      expect(seen.queryParameters, {'source': 'history', 'limit': '60'});
    });
  });
}
