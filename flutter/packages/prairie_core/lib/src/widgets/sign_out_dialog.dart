import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Apple TV's Sign Out question (Android #764): Cancel, Sign Out (keep the
/// server and open its sign-in screen), or Sign Out & Remove Server. Back
/// answers Cancel; focus starts on Cancel.
Future<SignOutChoice> showSignOutDialog(BuildContext context) async {
  final choice = await showDialog<SignOutChoice>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: PrairieColors.bgElevated,
      title: const Text('Sign Out', style: TextStyle(color: PrairieColors.ink)),
      content: const Text(
        'Choose whether to keep or remove this server from this TV.',
        style: TextStyle(color: PrairieColors.muted),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(SignOutChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(SignOutChoice.keepServer),
          child: const Text('Sign Out', style: TextStyle(color: PrairieColors.danger)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(SignOutChoice.removeServer),
          child: const Text('Sign Out & Remove Server', style: TextStyle(color: PrairieColors.danger)),
        ),
      ],
    ),
  );
  return choice ?? SignOutChoice.cancel;
}

/// Asks [showSignOutDialog]'s question, signs out through
/// [signOutRunnerProvider] and goes where the answer leads. A press while a
/// sign-out runs is ignored.
Future<void> requestSignOut(BuildContext context, WidgetRef ref) async {
  final runner = ref.read(signOutRunnerProvider);
  if (runner.running) return;
  final choice = await showSignOutDialog(context);
  if (choice == SignOutChoice.cancel || !context.mounted) return;

  // Read before anything waits: the screen that asked may be gone after.
  final routes = ref.read(routeProvider.notifier);
  final store = ref.read(serverRegistryStoreProvider);
  final result = await runner.run(
    removeServer: choice == SignOutChoice.removeServer,
    session: ref.read(sessionProvider),
    loadRegistry: store.load,
    saveRegistry: store.save,
    clearSession: ref.read(sessionProvider.notifier).clear,
  );
  switch (result) {
    case null:
      return;
    case SignOutRefused(:final message):
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
      }
    case SignedOut(removedServer: true):
      routes.goServers();
    case SignedOut(:final serverUrl, :final serverName, :final username, :final notice):
      routes.openLogin(
        serverUrl,
        serverName: serverName,
        initialUsername: username,
        notice: notice,
      );
  }
}
