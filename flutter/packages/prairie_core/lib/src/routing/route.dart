import '../models/auth.dart';
import '../models/catalog_item.dart';
import '../models/collection.dart';
import '../models/library.dart';
import '../models/live_tv_channel.dart';
import '../models/watch_detail.dart';

/// The app's full navigation state, as a sealed class.
///
/// Mirrors the `Route` discriminated union in src/App.tsx. There is
/// deliberately no router package here — a TV app has no URL bar or deep
/// linking, so a `switch` over this sealed class (see AppRootWidget) is a
/// closer, lower-ceremony port of the existing hand-rolled state machine.
sealed class Route {
  const Route();
}

class ServersRoute extends Route {
  const ServersRoute({this.back, this.autoScan});

  /// When `"home"`, a back action is available and returns to Home.
  final String? back;
  final bool? autoScan;
}

class ManualServerRoute extends Route {
  const ManualServerRoute({this.initialUrl});

  final String? initialUrl;
}

class ConnectRoute extends Route {
  const ConnectRoute({required this.serverUrl, this.serverName, this.initialUsername});

  final String serverUrl;
  final String? serverName;
  final String? initialUsername;
}

class ProfilesRoute extends Route {
  const ProfilesRoute({required this.auth});

  final AuthTokens auth;
}

class HomeRoute extends Route {
  const HomeRoute({this.restoreContentId});

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;
}

class LibrariesRoute extends Route {
  const LibrariesRoute();
}

class LibraryRoute extends Route {
  const LibraryRoute({required this.library, this.restoreContentId});

  final Library library;

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;
}

class CollectionsRoute extends Route {
  const CollectionsRoute();
}

class CollectionRoute extends Route {
  const CollectionRoute({required this.collection, this.restoreContentId});

  final CollectionCard collection;

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;
}

class SearchRoute extends Route {
  const SearchRoute({this.restoreContentId});

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;
}

class LiveTvRoute extends Route {
  const LiveTvRoute();
}

class LiveTvPlayerRoute extends Route {
  const LiveTvPlayerRoute({required this.channel, required this.back});

  final LiveTvChannel channel;
  final Route back;
}

class DetailRoute extends Route {
  const DetailRoute({required this.contentId, this.seed, required this.back});

  final String contentId;
  final CatalogItem? seed;
  final Route back;
}

class SettingsRoute extends Route {
  const SettingsRoute({required this.back});

  final Route back;
}

class PlayerRoute extends Route {
  const PlayerRoute({required this.launch, required this.back});

  final PlayerLaunch launch;
  final Route back;
}

/// The bottom-shell tab a route corresponds to, or null when the route
/// renders full-screen outside the shell (e.g. player, detail, settings).
///
/// Mirrors `shellTabFor` in src/App.tsx.
enum ShellTab { home, libraries, collections, search, livetv }

ShellTab? shellTabFor(Route route) => switch (route) {
  HomeRoute() => ShellTab.home,
  LibrariesRoute() || LibraryRoute() => ShellTab.libraries,
  CollectionsRoute() || CollectionRoute() => ShellTab.collections,
  SearchRoute() => ShellTab.search,
  LiveTvRoute() => ShellTab.livetv,
  _ => null,
};
