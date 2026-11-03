import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'route.dart';

/// Holds the app's current [Route] and exposes the navigation actions used
/// throughout the shell and screens.
///
/// Mirrors the `route`/`setRoute` state and the `goServers`/`openLogin`
/// helpers in src/App.tsx. Session-dependent actions (`disconnect`,
/// `handleSelectSaved`, `handleSelectDiscovery`) are added once the
/// storage/API layers are ported — this notifier only owns navigation.
class RouteNotifier extends Notifier<Route> {
  @override
  Route build() => const ServersRoute(autoScan: true);

  void go(Route route) => state = route;

  void goServers({bool autoScan = true}) => state = ServersRoute(autoScan: autoScan);

  void openLogin(String serverUrl, {String? serverName, String? initialUsername, String? notice}) {
    state = ConnectRoute(
      serverUrl: serverUrl,
      serverName: serverName,
      initialUsername: initialUsername,
      notice: notice,
    );
  }

  void back(Route to) => state = to;
}

final routeProvider = NotifierProvider<RouteNotifier, Route>(RouteNotifier.new);
