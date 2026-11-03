import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/route.dart';
import 'routing/route_notifier.dart';
import 'settings/profile_launch.dart';
import 'screens/calendar_screen.dart';
import 'screens/catalog_page_screen.dart';
import 'screens/collection_browse_screen.dart';
import 'screens/collections_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/for_you_screen.dart';
import 'screens/home_screen.dart';
import 'screens/item_detail_screen.dart';
import 'screens/libraries_screen.dart';
import 'screens/library_browse_screen.dart';
import 'screens/live_tv_player_screen.dart';
import 'screens/live_tv_screen.dart';
import 'screens/manual_server_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/player_screen.dart';
import 'screens/profiles_screen.dart';
import 'screens/search_screen.dart';
import 'screens/servers_screen.dart';
import 'screens/settings_screen.dart';
import 'state/session_provider.dart';
import 'theme/prairie_theme.dart';
import 'widgets/prairie_loading_indicator.dart';

/// Top-level app widget. Platform apps (`prairie_tizen`, `prairie_webos`)
/// only need `runApp(const ProviderScope(child: PrairieApp()))` in their
/// `main()` — everything else (routing, screens, theme) is shared here.
class PrairieApp extends StatelessWidget {
  const PrairieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prairie',
      theme: buildPrairieTheme(),
      builder: (context, child) => PrairieBackground(child: child ?? const SizedBox.shrink()),
      home: const _StartupGate(),
    );
  }
}

/// Restores a saved session (mirrors `initialRoute()`/the `session` useState
/// initializer in src/App.tsx) before the first real paint, then hands off
/// to [AppRoot].
class _StartupGate extends ConsumerStatefulWidget {
  const _StartupGate();

  @override
  ConsumerState<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<_StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await ref.read(sessionProvider.notifier).restore();
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    if (session != null) {
      final launch = await loadProfileLaunchBehavior(ref.read(sharedPreferencesProvider));
      if (!mounted) return;
      ref.read(routeProvider.notifier).go(
        showsWhoIsWatchingAtLaunch(launch)
            ? ProfilesRoute(auth: session.asAuthTokens, atLaunch: true)
            : const HomeRoute(),
      );
    }
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: PrairieLoadingIndicator()));
    }
    return const AppRoot();
  }
}

/// Root widget switching on the current [Route].
///
/// Mirrors the top-level `if (route.name === ...)` chain in src/App.tsx.
/// Screens still pending port stay as placeholders — see the sequencing plan.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider);
    return switch (route) {
      ServersRoute(:final autoScan, :final back) => ServersScreen(autoScan: autoScan ?? true, canReturnHome: back == 'home'),
      ManualServerRoute(:final initialUrl) => ManualServerScreen(initialUrl: initialUrl),
      ConnectRoute(:final serverUrl, :final serverName, :final initialUsername, :final notice) => ConnectScreen(
        serverUrl: serverUrl,
        serverName: serverName,
        initialUsername: initialUsername,
        notice: notice,
      ),
      ProfilesRoute(:final auth, :final atLaunch) => ProfilesScreen(auth: auth, atLaunch: atLaunch),
      HomeRoute(:final restoreContentId, :final restoreExploreSectionId) =>
          HomeScreen(restoreContentId: restoreContentId, restoreExploreSectionId: restoreExploreSectionId),
      // Keyed by type: switching library tabs builds a fresh list.
      LibrariesRoute(:final type) => LibrariesScreen(key: ValueKey(type), type: type),
      LibraryRoute(:final library, :final tab, :final restoreContentId) =>
          LibraryBrowseScreen(library: library, tab: tab, restoreContentId: restoreContentId),
      CollectionsRoute(:final tab) => CollectionsScreen(tab: tab),
      CollectionRoute(:final collection, :final tab, :final restoreContentId) => CollectionBrowseScreen(
        title: collection.displayTitle,
        collectionId: collection.id,
        libraryId: collection.libraryId,
        tab: tab,
        restoreContentId: restoreContentId,
      ),
      SearchRoute(:final restoreContentId) => SearchScreen(restoreContentId: restoreContentId),
      CalendarRoute(:final restoreContentId) => CalendarScreen(restoreContentId: restoreContentId),
      ForYouRoute(:final restoreContentId) => ForYouScreen(restoreContentId: restoreContentId),
      LiveTvRoute(:final tab, :final restoreChannelId) => LiveTvScreen(initialTab: tab, restoreChannelId: restoreChannelId),
      LiveTvPlayerRoute(:final channel, :final back) => LiveTvPlayerScreen(channel: channel, back: back),
      // Keyed by title: a More like this pick, or Back to the title a chain
      // started from, loads that title instead of keeping the last one.
      DetailRoute(:final contentId, :final seed, :final back, :final fromMoreLikeThis) => ItemDetailScreen(
        key: ValueKey(contentId),
        contentId: contentId,
        seed: seed,
        back: back,
        fromMoreLikeThis: fromMoreLikeThis,
      ),
      final CatalogPageRoute page => CatalogPageScreen(route: page),
      SettingsRoute(:final back) => SettingsScreen(back: back),
      NotificationsRoute(:final back) => NotificationsScreen(back: back),
      // Keyed by launch: next/previous episode swaps in a fresh player.
      PlayerRoute(:final launch, :final back) => PlayerScreen(key: ObjectKey(launch), launch: launch, back: back),
    };
  }
}
