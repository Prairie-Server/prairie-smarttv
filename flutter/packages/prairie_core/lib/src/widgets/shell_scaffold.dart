import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// A `Scaffold` pre-wired with [ShellNav], so each browse screen only needs
/// to supply its [active] tab and [body] rather than repeating the
/// navigate/profiles/settings/disconnect wiring.
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({super.key, required this.active, required this.body});

  final ShellTab active;
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider)!;
    final liveTvAvailable = ref.watch(liveTvAvailableProvider).valueOrNull ?? (active == ShellTab.livetv);
    // Back on any tab other than Home returns to Home instead of exiting the
    // app — only Home's own back falls through to the platform default.
    return PopScope(
      canPop: active == ShellTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(routeProvider.notifier).go(const HomeRoute());
      },
      child: Scaffold(
      appBar: ShellNav(
        active: active,
        profileName: session.profileName,
        profileAvatarUrl: session.profileAvatarUrl,
        showLiveTv: liveTvAvailable,
        onNavigate: (tab) => ref.read(routeProvider.notifier).go(switch (tab) {
          ShellTab.home => const HomeRoute(),
          ShellTab.libraries => const LibrariesRoute(),
          ShellTab.collections => const CollectionsRoute(),
          ShellTab.search => const SearchRoute(),
          ShellTab.livetv => const LiveTvRoute(),
        }),
        onProfiles: () => ref.read(routeProvider.notifier).go(ProfilesRoute(auth: session.asAuthTokens)),
        onSettings: () => ref.read(routeProvider.notifier).go(SettingsRoute(back: switch (active) {
          ShellTab.home => const HomeRoute(),
          ShellTab.libraries => const LibrariesRoute(),
          ShellTab.collections => const CollectionsRoute(),
          ShellTab.search => const SearchRoute(),
          ShellTab.livetv => const LiveTvRoute(),
        })),
        onDisconnect: () async {
          await ref.read(sessionProvider.notifier).clear();
          if (!context.mounted) return;
          ref.read(routeProvider.notifier).goServers();
        },
      ),
      body: body,
      ),
    );
  }
}
