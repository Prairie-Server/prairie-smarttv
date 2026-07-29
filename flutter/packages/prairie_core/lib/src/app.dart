import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/route.dart';
import 'routing/route_notifier.dart';
import 'screens/collection_browse_screen.dart';
import 'screens/collections_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/item_detail_screen.dart';
import 'screens/libraries_screen.dart';
import 'screens/library_browse_screen.dart';
import 'screens/live_tv_player_screen.dart';
import 'screens/live_tv_screen.dart';
import 'screens/manual_server_screen.dart';
import 'screens/player_screen.dart';
import 'screens/profiles_screen.dart';
import 'screens/search_screen.dart';
import 'screens/servers_screen.dart';
import 'screens/settings_screen.dart';
import 'state/session_provider.dart';
import 'theme/prairie_theme.dart';

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
    if (ref.read(sessionProvider) != null) {
      ref.read(routeProvider.notifier).go(const HomeRoute());
    }
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
      ServersRoute(:final autoScan) => ServersScreen(autoScan: autoScan ?? true),
      ManualServerRoute(:final initialUrl) => ManualServerScreen(initialUrl: initialUrl),
      ConnectRoute(:final serverUrl, :final serverName, :final initialUsername) => ConnectScreen(
        serverUrl: serverUrl,
        serverName: serverName,
        initialUsername: initialUsername,
      ),
      ProfilesRoute(:final auth) => ProfilesScreen(auth: auth),
      HomeRoute() => const HomeScreen(),
      LibrariesRoute() => const LibrariesScreen(),
      LibraryRoute(:final library) => LibraryBrowseScreen(library: library),
      CollectionsRoute() => const CollectionsScreen(),
      CollectionRoute(:final collection) => CollectionBrowseScreen(
        title: collection.displayTitle,
        collectionId: collection.id,
        libraryId: collection.libraryId,
      ),
      SearchRoute() => const SearchScreen(),
      LiveTvRoute() => const LiveTvScreen(),
      LiveTvPlayerRoute(:final channel, :final back) => LiveTvPlayerScreen(channel: channel, back: back),
      DetailRoute(:final contentId, :final seed, :final back) => ItemDetailScreen(contentId: contentId, seed: seed, back: back),
      SettingsRoute(:final back) => SettingsScreen(back: back),
      PlayerRoute(:final launch, :final back) => PlayerScreen(launch: launch, back: back),
    };
  }
}
