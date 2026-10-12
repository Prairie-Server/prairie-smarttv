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

  test('renameCollection PATCHes the trimmed name with If-Match', () async {
    await renameCollection(client, _session, 'c1', '  Rainy days ');
    final req = adapter.requests.single;
    expect(req.method, 'PATCH');
    expect(req.uri.path, '/api/v2/collections/c1');
    expect(req.data, {'name': 'Rainy days'});
    expect(req.headers['If-Match'], '*');
  });

  test('a blank collection name is rejected without a request', () async {
    await expectLater(createCollection(client, _session, '   '), throwsArgumentError);
    expect(adapter.requests, isEmpty);
  });

  test('canEditCollection needs capabilities and the creating profile', () {
    const allowed = CollectionCapabilities(allowed: true);
    const own = CollectionCard(id: 'c1', creatorProfileId: 'p1');
    expect(canEditCollection(allowed, own, 'p1'), isTrue);
    expect(canEditCollection(null, own, 'p1'), isFalse);
    expect(canEditCollection(const CollectionCapabilities(allowed: false), own, 'p1'), isFalse);
    expect(canEditCollection(allowed, const CollectionCard(id: 'c2', creatorProfileId: 'p2'), 'p1'), isFalse);
    expect(canEditCollection(allowed, const CollectionCard(id: 'c3', libraryId: 4), 'p1'), isFalse);
  });
}
