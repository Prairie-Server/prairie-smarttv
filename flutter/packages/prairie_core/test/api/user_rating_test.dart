import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

const _session = PrairieSession(
  serverUrl: 'https://prairie.example',
  accessToken: 'tok',
  username: 'u',
  profileId: 'p1',
);

void main() {
  late FakeHttpAdapter adapter;
  late ApiClient client;

  setUp(() {
    adapter = FakeHttpAdapter((_) => ResponseBody.fromString('', 204));
    client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
  });

  test('setUserRating PUTs the stars to the v2 ratings route', () async {
    await setUserRating(client, _session, 'movie:heat-1995', 4);
    final req = adapter.requests.single;
    expect(req.method, 'PUT');
    expect(Uri.decodeComponent(req.uri.path), '/api/v2/ratings/movie:heat-1995');
    expect(req.data, {'rating': 4});
  });

  test('setUserRating with null DELETEs the rating', () async {
    await setUserRating(client, _session, 'movie:heat-1995', null);
    final req = adapter.requests.single;
    expect(req.method, 'DELETE');
    expect(req.data, isNull);
  });

  test('setUserRating rejects out-of-range stars without a request', () {
    expect(() => setUserRating(client, _session, 'm', 0), throwsArgumentError);
    expect(() => setUserRating(client, _session, 'm', 6), throwsArgumentError);
    expect(adapter.requests, isEmpty);
  });

  test('ItemDetail parses user_rating', () {
    final base = {'content_id': 'movie:heat-1995', 'title': 'Heat', 'type': 'movie'};
    expect(ItemDetail.fromJson({...base, 'user_rating': 3}).userRating, 3);
    expect(ItemDetail.fromJson(base).userRating, isNull);
  });
}
