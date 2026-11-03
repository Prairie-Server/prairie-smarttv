import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// A `Scaffold` pre-wired with [ShellNav], so each browse screen only needs
/// to supply its [active] tab and [body] rather than repeating the
/// navigate/profile-menu wiring.
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({super.key, required this.active, required this.body, this.escapeDownFocus, this.onBack});

  /// The highlighted tab; null on a page reached from a tab's content.
  final ShellTab? active;
  final Widget body;

  /// Forwarded to [ShellNav.escapeDownFocus] — see its doc for why this is a
  /// resolver rather than a fixed [FocusNode].
  final FocusNode? Function()? escapeDownFocus;

  /// When set, Back runs this (e.g. to leave an in-screen mode) instead of
  /// the tab's default.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider)!;
    final liveTvAvailable = ref.watch(liveTvAvailableProvider).valueOrNull ?? false;
    final libraries = ref.watch(librariesProvider).valueOrNull ?? const <Library>[];
    final unreadCount = (ref.watch(notificationUnreadCountProvider).valueOrNull ?? 0) +
        (ref.watch(appUpdateProvider).valueOrNull != null ? 1 : 0);
    // Back on any tab other than Home returns to Home instead of exiting the
    // app — only Home's own back falls through to the platform default.
    return PopScope(
      canPop: active == ShellTab.home && onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (onBack != null) {
          onBack!();
        } else {
          ref.read(routeProvider.notifier).go(const HomeRoute());
        }
      },
      child: Scaffold(
      appBar: ShellNav(
        tabs: visibleShellTabs(libraries: libraries, liveTv: liveTvAvailable, active: active),
        active: active,
        profileName: session.profileName,
        profileAvatarUrl: session.profileAvatarUrl,
        onNavigate: (tab) => ref.read(routeProvider.notifier).go(routeForShellTab(tab)),
        onProfiles: () => ref.read(routeProvider.notifier).go(ProfilesRoute(auth: session.asAuthTokens)),
        onHistory: () => ref.read(routeProvider.notifier).go(
          CatalogPageRoute(title: 'History', source: CatalogPageSource.history, back: ref.read(routeProvider)),
        ),
        onSettings: () => ref.read(routeProvider.notifier).go(SettingsRoute(back: ref.read(routeProvider))),
        onSwitchServer: () => ref.read(routeProvider.notifier).go(ServersRoute.switchServer),
        onSignOut: () async {
          await ref.read(sessionProvider.notifier).clear();
          if (!context.mounted) return;
          ref.read(routeProvider.notifier).goServers();
        },
        escapeDownFocus: escapeDownFocus,
        unreadCount: unreadCount,
        onNotifications: () => ref.read(routeProvider.notifier).go(NotificationsRoute(back: ref.read(routeProvider))),
      ),
      body: body,
      ),
    );
  }
}
