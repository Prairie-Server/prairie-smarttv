import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

const _missing = RequestTitle(tmdbId: 7, mediaType: 'movie', title: 'Dune', year: 2021);
const _inLibrary = RequestTitle(
  tmdbId: 8,
  mediaType: 'series',
  title: 'Show',
  availability: 'available',
  libraryContentId: 'c8',
);

void main() {
  test('a title in the library opens its library page, others their request page', () {
    const back = RequestsRoute(back: HomeRoute());
    final library = requestTitleDestination(_inLibrary, back);
    expect(library, isA<DetailRoute>());
    expect((library as DetailRoute).contentId, 'c8');
    expect(library.back, same(back));
    final request = requestTitleDestination(_missing, back);
    expect(request, isA<RequestTitleRoute>());
    expect((request as RequestTitleRoute).title, same(_missing));
  });

  test('available with no library id still opens the request page', () {
    const odd = RequestTitle(tmdbId: 9, mediaType: 'movie', title: 'X', availability: 'available');
    expect(requestTitleDestination(odd, const HomeRoute()), isA<RequestTitleRoute>());
  });

  test('card captions show the library, then the request state, then the year', () {
    expect(requestTitleCaption(_inLibrary), 'In your library');
    expect(requestTitleCaption(_missing), '2021 · Movie');
    expect(requestTitleCaption(_missing.withRequest(const RequestState(state: 'processing'))), 'Processing');
    expect(requestTitleCaption(const RequestTitle(tmdbId: 1, mediaType: 'series', title: 'S')), 'Series');
  });

  test('the requests screens are the ones that close when requests turn off', () {
    const hub = RequestsRoute(back: HomeRoute());
    expect(isRequestsRoute(hub), isTrue);
    expect(isRequestsRoute(const RequestsRowRoute(rowKey: 'k', title: 'K', back: hub)), isTrue);
    expect(isRequestsRoute(const RequestTitleRoute(title: _missing, back: hub)), isTrue);
    expect(isRequestsRoute(const HomeRoute()), isFalse);
    expect(shellTabFor(hub), isNull);
  });

  test('returning to the hub or a row restores the opened card', () {
    const hub = RequestsRoute(back: HomeRoute());
    expect(hub.withRestore('movie:7').restoreKey, 'movie:7');
    expect(hub.withRestore('movie:7').back, isA<HomeRoute>());
    const row = RequestsRowRoute(rowKey: 'trending', title: 'Trending', back: hub);
    final restored = row.withRestore('series:8');
    expect(restored.rowKey, 'trending');
    expect(restored.restoreKey, 'series:8');
    expect(_missing.key, 'movie:7');
  });
}
