import 'package:prairie_core/src/api/box_sets_api.dart';

import '../models/auth.dart';
import '../models/catalog_item.dart';
import '../models/collection.dart';
import '../models/library.dart';
import '../models/live_tv_channel.dart';
import '../models/watch_detail.dart';
import 'shell_tabs.dart';

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

  /// Switch Server from the profile menu: the session stays, so Back can
  /// return Home.
  static const switchServer = ServersRoute(back: 'home', autoScan: false);

  /// When `"home"`, a back action is available and returns to Home.
  final String? back;
  final bool? autoScan;
}

class ManualServerRoute extends Route {
  const ManualServerRoute({this.initialUrl});

  final String? initialUrl;
}

class ConnectRoute extends Route {
  const ConnectRoute({required this.serverUrl, this.serverName, this.initialUsername, this.notice});

  final String serverUrl;
  final String? serverName;
  final String? initialUsername;

  /// Shown on arrival, e.g. a sign-out that couldn't remove the server.
  final String? notice;
}

class ProfilesRoute extends Route {
  const ProfilesRoute({required this.auth, this.atLaunch = false});

  final AuthTokens auth;

  /// Shown at launch because Profile Selection is Every Time: there is no
  /// profile to cancel back to.
  final bool atLaunch;
}

class HomeRoute extends Route {
  const HomeRoute({this.restoreContentId, this.restoreExploreSectionId});

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;

  /// When returning from a row's full page, focus that row's Explore all card.
  final String? restoreExploreSectionId;
}

/// A library-type top-bar tab (Movies, Series, Music, Audiobooks): the
/// libraries of that type.
class LibrariesRoute extends Route {
  const LibrariesRoute({required this.type});

  final LibraryTabType type;
}

class LibraryRoute extends Route {
  const LibraryRoute({required this.library, required this.tab, this.restoreContentId});

  final Library library;

  /// The library-type tab the library was opened from; Back returns there.
  final LibraryTabType tab;

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;
}

class CollectionsRoute extends Route {
  const CollectionsRoute({required this.tab});

  /// The library-type tab Collections was opened from; Back returns there.
  final LibraryTabType tab;
}

class CollectionRoute extends Route {
  const CollectionRoute({required this.collection, required this.tab, this.restoreContentId});

  final CollectionCard collection;
  final LibraryTabType tab;

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;
}

class SearchRoute extends Route {
  const SearchRoute({this.restoreContentId});

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;
}

class CalendarRoute extends Route {
  const CalendarRoute({this.restoreContentId});

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;
}

class ForYouRoute extends Route {
  const ForYouRoute({this.restoreContentId});

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;
}

enum LiveTvTab { channels, guide, recordings }

class LiveTvRoute extends Route {
  const LiveTvRoute({this.tab = LiveTvTab.guide, this.restoreChannelId});

  /// Tab to open on — the one the viewer tuned from, when returning.
  final LiveTvTab tab;

  /// When returning from the live player, focus this channel's row instead
  /// of the top of the list.
  final String? restoreChannelId;
}

class LiveTvPlayerRoute extends Route {
  const LiveTvPlayerRoute({required this.channel, required this.back});

  final LiveTvChannel channel;
  final Route back;
}

class DetailRoute extends Route {
  const DetailRoute({required this.contentId, this.seed, required this.back, this.fromMoreLikeThis = false});

  final String contentId;
  final CatalogItem? seed;
  final Route back;

  /// Opened from another detail page's More like this rail. [back] is then
  /// the title the chain started from; see [moreLikeThisRoute].
  final bool fromMoreLikeThis;
}

/// Where picking [item] from [current]'s More like this rail goes, or null
/// when nothing should open (a repeat pick of the title already on screen).
///
/// The first pick pushes a new page; later picks from a rail-opened page
/// replace it, so Back returns to the starting title and then to wherever
/// that title was opened from. Picking the starting title again goes back to
/// it instead of stacking a copy. Mirrors Android's #737.
Route? moreLikeThisRoute(DetailRoute current, CatalogItem item) {
  if (item.contentId == current.contentId) return null;
  if (!current.fromMoreLikeThis) {
    return DetailRoute(contentId: item.contentId, seed: item, back: current, fromMoreLikeThis: true);
  }
  final start = current.back;
  if (start is DetailRoute && start.contentId == item.contentId) return start;
  return DetailRoute(contentId: item.contentId, seed: item, back: start, fromMoreLikeThis: true);
}

/// A movie box set's page: its films in release order.
class BoxSetRoute extends Route {
  const BoxSetRoute({required this.boxSet, required this.back, this.restoreContentId});

  /// The box set as the card that opened it knew it; the page reloads it.
  final BoxSet boxSet;
  final Route back;

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;

  BoxSetRoute withRestore(String contentId) => BoxSetRoute(boxSet: boxSet, back: back, restoreContentId: contentId);
}

/// What a [CatalogPageRoute] pages through.
enum CatalogPageSource {
  /// A Home row's full list (`source=section&scope=home`).
  homeSection,

  /// The profile's watch history (`source=history`).
  history,
}

/// A full, paged poster grid: a Home row's Explore all page, or History.
class CatalogPageRoute extends Route {
  const CatalogPageRoute({
    required this.title,
    required this.source,
    this.sectionId,
    required this.back,
    this.restoreContentId,
  });

  final String title;
  final CatalogPageSource source;

  /// The Home section, for [CatalogPageSource.homeSection].
  final String? sectionId;
  final Route back;

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;

  CatalogPageRoute withRestore(String contentId) => CatalogPageRoute(
    title: title,
    source: source,
    sectionId: sectionId,
    back: back,
    restoreContentId: contentId,
  );
}

class SettingsRoute extends Route {
  const SettingsRoute({required this.back});

  final Route back;
}

class NotificationsRoute extends Route {
  const NotificationsRoute({required this.back});

  final Route back;
}

class PlayerRoute extends Route {
  const PlayerRoute({required this.launch, required this.back});

  final PlayerLaunch launch;
  final Route back;
}

/// The top-bar tab a route corresponds to, or null when the route renders
/// full-screen outside the shell (e.g. player, detail, settings).
///
/// Mirrors `shellTabFor` in src/App.tsx.
ShellTab? shellTabFor(Route route) => switch (route) {
  HomeRoute() => ShellTab.home,
  LibrariesRoute(:final type) || LibraryRoute(tab: final type) => type.shellTab,
  CollectionsRoute(tab: final type) || CollectionRoute(tab: final type) => type.shellTab,
  SearchRoute() => ShellTab.search,
  LiveTvRoute() => ShellTab.livetv,
  CalendarRoute() => ShellTab.calendar,
  ForYouRoute() => ShellTab.forYou,
  _ => null,
};

/// The route a top-bar tab opens.
Route routeForShellTab(ShellTab tab) => switch (tab) {
  ShellTab.search => const SearchRoute(),
  ShellTab.home => const HomeRoute(),
  ShellTab.movies => const LibrariesRoute(type: LibraryTabType.movies),
  ShellTab.series => const LibrariesRoute(type: LibraryTabType.series),
  ShellTab.music => const LibrariesRoute(type: LibraryTabType.music),
  ShellTab.audiobooks => const LibrariesRoute(type: LibraryTabType.audiobooks),
  ShellTab.forYou => const ForYouRoute(),
  ShellTab.calendar => const CalendarRoute(),
  ShellTab.livetv => const LiveTvRoute(),
};
