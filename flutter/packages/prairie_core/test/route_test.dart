import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('shellTabFor', () {
    test('maps browse routes to their tab', () {
      expect(shellTabFor(const HomeRoute()), ShellTab.home);
      expect(shellTabFor(const LibrariesRoute(type: LibraryTabType.movies)), ShellTab.movies);
      expect(shellTabFor(const LibrariesRoute(type: LibraryTabType.audiobooks)), ShellTab.audiobooks);
      expect(shellTabFor(const SearchRoute()), ShellTab.search);
      expect(shellTabFor(const ForYouRoute()), ShellTab.forYou);
      expect(shellTabFor(const CalendarRoute()), ShellTab.calendar);
      expect(shellTabFor(const LiveTvRoute()), ShellTab.livetv);
    });

    test('keeps a live TV route returning to a channel on the live TV tab', () {
      expect(shellTabFor(const LiveTvRoute(tab: LiveTvTab.channels, restoreChannelId: 'ch-7')), ShellTab.livetv);
    });

    test('maps a library route to the library-type tab it was opened from', () {
      const library = Library(id: 1, name: 'Everything', type: 'mixed');
      expect(shellTabFor(const LibraryRoute(library: library, tab: LibraryTabType.series)), ShellTab.series);
    });

    test('maps collections to the tab they were opened from', () {
      expect(shellTabFor(const CollectionsRoute(tab: LibraryTabType.movies)), ShellTab.movies);
    });

    test('returns null for full-screen routes outside the shell', () {
      expect(shellTabFor(const ServersRoute()), null);
      expect(shellTabFor(const ManualServerRoute()), null);
      expect(shellTabFor(const SettingsRoute(back: HomeRoute())), null);
      expect(
        shellTabFor(const CatalogPageRoute(title: 'History', source: CatalogPageSource.history, back: HomeRoute())),
        null,
      );
    });

    test('every tab opens a route that maps back to it', () {
      for (final tab in ShellTab.values) {
        expect(shellTabFor(routeForShellTab(tab)), tab, reason: '$tab');
      }
    });
  });

  group('visibleShellTabs', () {
    const movies = Library(id: 1, name: 'Films', type: 'movie');
    const shows = Library(id: 2, name: 'TV', type: 'series');
    const music = Library(id: 3, name: 'Music', type: 'music');
    const books = Library(id: 4, name: 'Books', type: 'audiobook');

    test('fixes the order: Search, Home, library types, For You, Calendar, Live TV', () {
      expect(visibleShellTabs(libraries: const [books, music, shows, movies], liveTv: true), [
        ShellTab.search,
        ShellTab.home,
        ShellTab.movies,
        ShellTab.series,
        ShellTab.music,
        ShellTab.audiobooks,
        ShellTab.forYou,
        ShellTab.calendar,
        ShellTab.livetv,
      ]);
    });

    test('shows a library-type tab only when a matching library exists', () {
      expect(visibleShellTabs(libraries: const [shows], liveTv: false), [
        ShellTab.search,
        ShellTab.home,
        ShellTab.series,
        ShellTab.forYou,
        ShellTab.calendar,
      ]);
    });

    test('a mixed library shows both Movies and Series', () {
      const mixed = Library(id: 5, name: 'All', type: 'mixed');
      final tabs = visibleShellTabs(libraries: const [mixed], liveTv: false);
      expect(tabs, containsAllInOrder([ShellTab.movies, ShellTab.series]));
      expect(tabs, isNot(contains(ShellTab.music)));
    });

    test('keeps the active tab while libraries are still loading', () {
      expect(visibleShellTabs(libraries: const [], liveTv: false, active: ShellTab.music), contains(ShellTab.music));
      expect(visibleShellTabs(libraries: const [], liveTv: false, active: ShellTab.livetv), contains(ShellTab.livetv));
    });

    test('has no Libraries, Collections or Requests tab', () {
      final names = visibleShellTabs(libraries: const [movies], liveTv: true).map((t) => t.name);
      expect(names, isNot(contains('libraries')));
      expect(names, isNot(contains('collections')));
      expect(names, isNot(contains('requests')));
    });
  });

  group('LibraryTabType', () {
    test('classifies library types', () {
      expect(LibraryTabType.forLibrary(const Library(id: 1, name: 'a', type: 'Movies')), LibraryTabType.movies);
      expect(LibraryTabType.forLibrary(const Library(id: 1, name: 'a', type: 'tv')), LibraryTabType.series);
      expect(LibraryTabType.forLibrary(const Library(id: 1, name: 'a', type: 'album')), LibraryTabType.music);
      expect(LibraryTabType.forLibrary(const Library(id: 1, name: 'a', type: 'audiobooks')), LibraryTabType.audiobooks);
      expect(LibraryTabType.forLibrary(const Library(id: 1, name: 'a', type: 'photo')), null);
    });
  });

  group('moreLikeThisRoute', () {
    CatalogItem item(String id) => CatalogItem(contentId: id, type: 'movie', title: id);
    const home = HomeRoute(restoreContentId: 'a');
    const start = DetailRoute(contentId: 'a', back: home);

    test('the first pick pushes a page that goes back to the starting title', () {
      final b = moreLikeThisRoute(start, item('b')) as DetailRoute;
      expect(b.contentId, 'b');
      expect(b.fromMoreLikeThis, isTrue);
      expect(b.back, same(start));
    });

    test('later picks replace the pushed page, so Back takes two steps', () {
      final b = moreLikeThisRoute(start, item('b')) as DetailRoute;
      final c = moreLikeThisRoute(b, item('c')) as DetailRoute;
      final d = moreLikeThisRoute(c, item('d')) as DetailRoute;
      expect(d.contentId, 'd');
      expect(d.back, same(start));
      expect((d.back as DetailRoute).back, same(home));
    });

    test('picking the starting title again goes back to it', () {
      final b = moreLikeThisRoute(start, item('b')) as DetailRoute;
      expect(moreLikeThisRoute(b, item('a')), same(start));
    });

    test('a repeat pick of the title on screen opens nothing', () {
      expect(moreLikeThisRoute(start, item('a')), isNull);
    });
  });

  group('RouteNotifier', () {
    test('starts on the servers route with auto-scan enabled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final route = container.read(routeProvider);
      expect(route, isA<ServersRoute>());
      expect((route as ServersRoute).autoScan, true);
    });

    test('goServers defaults to auto-scan on', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(routeProvider.notifier).goServers();
      final route = container.read(routeProvider) as ServersRoute;
      expect(route.autoScan, true);
    });

    test('openLogin navigates to connect with the given server details', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(routeProvider.notifier)
          .openLogin('https://prairie.local', serverName: 'Living Room');

      final route = container.read(routeProvider) as ConnectRoute;
      expect(route.serverUrl, 'https://prairie.local');
      expect(route.serverName, 'Living Room');
    });
  });

  test('a box set page is full-screen and comes back to the film opened from it', () {
    const boxSet = BoxSet(id: '119', libraryId: '7', title: 'Box');
    const route = BoxSetRoute(boxSet: boxSet, back: SearchRoute());
    expect(shellTabFor(route), isNull);
    final restored = route.withRestore('m2');
    expect(restored.restoreContentId, 'm2');
    expect(restored.boxSet, same(boxSet));
    expect(restored.back, isA<SearchRoute>());
  });
}
