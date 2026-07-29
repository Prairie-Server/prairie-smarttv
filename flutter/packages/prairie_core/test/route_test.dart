import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('shellTabFor', () {
    test('maps browse routes to their tab', () {
      expect(shellTabFor(const HomeRoute()), ShellTab.home);
      expect(shellTabFor(const LibrariesRoute()), ShellTab.libraries);
      expect(shellTabFor(const CollectionsRoute()), ShellTab.collections);
      expect(shellTabFor(const SearchRoute()), ShellTab.search);
      expect(shellTabFor(const LiveTvRoute()), ShellTab.livetv);
    });

    test('maps a library route to the libraries tab, like its list route', () {
      const library = Library(id: 1, name: 'Movies', type: 'movie');
      expect(shellTabFor(const LibraryRoute(library: library)), ShellTab.libraries);
    });

    test('returns null for full-screen routes outside the shell', () {
      expect(shellTabFor(const ServersRoute()), null);
      expect(shellTabFor(const ManualServerRoute()), null);
      expect(shellTabFor(const SettingsRoute(back: HomeRoute())), null);
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
}
