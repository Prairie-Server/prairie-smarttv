import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/notifications_api.dart';
import '../platform/app_update.dart';
import '../platform/client_identity.dart';
import '../routing/route.dart';
import '../routing/route_notifier.dart';
import 'session_provider.dart';

/// The acting profile's unread notification count for the nav badge.
/// Fetched once per session and again whenever navigation comes back into
/// the shell (from detail, player, settings or the inbox itself) — no
/// polling. Errors read as zero.
final notificationUnreadCountProvider = FutureProvider<int>((ref) async {
  ref.listen(routeProvider.select((route) => shellTabFor(route) != null), (wasInShell, inShell) {
    if (inShell && wasInShell == false) ref.invalidateSelf();
  });
  final session = ref.watch(sessionProvider);
  if (session == null) return 0;
  try {
    return await fetchNotificationUnreadCount(ref.read(apiClientProvider), session);
  } catch (_) {
    return 0;
  }
});

/// A newer sideload release, if any — see [AppUpdateChecker]. Checked once
/// per app run (and at most once a day against GitHub).
final appUpdateProvider = FutureProvider<AvailableUpdate?>((ref) {
  return AppUpdateChecker(
    prefs: ref.read(sharedPreferencesProvider),
    dio: ref.read(apiClientProvider).dio,
    currentVersion: stampedAppVersion,
  ).check();
});
