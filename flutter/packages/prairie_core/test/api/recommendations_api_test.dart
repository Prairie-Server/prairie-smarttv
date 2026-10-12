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

String _card(String id, {bool favorite = false}) =>
    '{"content_id":"$id","title":"$id","type":"movie","status":"available","genres":[],"keywords":[]'
    '${favorite ? ',"user_state":{"is_favorite":true}' : ''}}';

CatalogItem _item(String id, {bool favorite = false}) =>
    CatalogItem(contentId: id, type: 'movie', title: id, userState: favorite ? const MediaItemUserState(isFavorite: true) : null);

void main() {
  test('discover reads rows, drops empty ones and spots personalized kinds', () async {
    final client = _clientWith(
      (_) => jsonResponse(
        '{"items":['
        '{"type":"cluster","title":"For You","kind":"for-you-main","items":[${_card('a')}]},'
        '{"type":"popular","title":"Popular","kind":"popular","items":[${_card('b')}]},'
        '{"type":"genre_sampler","title":"Top Drama","kind":"genre","key":"Drama","items":[]}]}',
        200,
      ),
    );
    final rows = await fetchDiscover(client, _session);
    expect(rows.map((r) => r.kind), ['for-you-main', 'popular']);
    expect(rows.map((r) => r.personalized), [true, false]);
    expect(rows.where((r) => !homeDuplicateRowKinds.contains(r.kind)).map((r) => r.title), ['Popular']);
  });

  test('taste-seed items follow the cursor until has_more is false', () async {
    final seen = <Uri>[];
    final client = _clientWith((o) {
      seen.add(o.uri);
      return o.uri.queryParameters['cursor'] == null
          ? jsonResponse('{"items":[${_card('a')}],"page":{"has_more":true,"next_cursor":"c2"}}', 200)
          : jsonResponse('{"items":[${_card('b')}],"page":{"has_more":false}}', 200);
    });
    final first = await fetchTasteSeedItems(client, _session);
    expect(first.nextCursor, 'c2');
    final second = await fetchTasteSeedItems(client, _session, cursor: first.nextCursor);
    expect(second.items.single.contentId, 'b');
    expect(second.nextCursor, isNull);
    expect(seen.last.queryParameters['cursor'], 'c2');
  });

  test('taste-seed submit posts item_ids', () async {
    late RequestOptions seen;
    final client = _clientWith((o) {
      seen = o;
      return jsonResponse('{"added":2}', 200);
    });
    await submitTasteSeed(client, _session, ['a', 'b']);
    expect(seen.method, 'POST');
    expect(seen.path, endsWith('/api/v2/recommendations/taste-seed'));
    expect(seen.data, {'item_ids': ['a', 'b']});
  });

  test('taste picks start from favourites and send only new picks', () {
    final picks = TastePicks()..addPage([_item('fav', favorite: true), _item('x'), _item('y')]);
    expect(picks.isPicked('fav'), isTrue);
    expect(picks.count, 1);

    picks
      ..toggle('x')
      ..toggle('y')
      ..toggle('y')
      ..toggle('fav');
    expect(picks.isPicked('fav'), isFalse);
    expect(picks.count, 1);
    expect(picks.newPicks, ['x']);

    // A later page's favourite stays deselected if the user already said no.
    picks.addPage([_item('fav', favorite: true)]);
    expect(picks.isPicked('fav'), isFalse);
  });
}
