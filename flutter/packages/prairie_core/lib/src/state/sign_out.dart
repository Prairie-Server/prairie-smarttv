import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth.dart';
import '../models/server_entry.dart';
import '../storage/server_registry_store.dart';

/// The Sign Out dialog's answer (Apple TV / Android #764).
enum SignOutChoice { cancel, keepServer, removeServer }

/// How a sign-out ended.
sealed class SignOutResult {
  const SignOutResult();
}

/// Signed out. [removedServer] is false when the server was kept, or when
/// removing it failed ([notice] then says so): the TV opens the server's
/// sign-in screen. When the server went, the server list opens.
class SignedOut extends SignOutResult {
  const SignedOut({
    required this.serverUrl,
    required this.removedServer,
    this.serverName,
    this.username,
    this.notice,
  });

  final String serverUrl;
  final bool removedServer;
  final String? serverName;
  final String? username;
  final String? notice;
}

/// Nobody was signed out; stay where you are and show [message].
class SignOutRefused extends SignOutResult {
  const SignOutRefused(this.message);
  final String message;
}

// prairie-apple `AppRouter.requestSignOut` wording.
const signOutSessionChangedMessage = 'The active session changed. Try signing out again.';
const signOutLocalFailedMessage =
    "Prairie couldn't clear the saved sign-in on this device. Please try signing out again.";
const removeServerFailedMessage = "Prairie couldn't remove the saved server. Please try again.";

/// The one TV sign-out behind the profile menu and Settings. A second
/// request while one runs is ignored ([run] returns null).
class SignOutRunner {
  bool _running = false;

  bool get running => _running;

  /// Signs [session] out and, with [removeServer], forgets its server.
  ///
  /// The server is removed first and the session cleared last, so the caller
  /// can navigate straight after this returns without a frame drawn signed
  /// out on a signed-in screen.
  Future<SignOutResult?> run({
    required bool removeServer,
    required PrairieSession? session,
    required Future<ServerRegistry> Function() loadRegistry,
    required Future<void> Function(ServerRegistry registry) saveRegistry,
    required Future<void> Function() clearSession,
  }) async {
    if (_running) return null;
    _running = true;
    try {
      if (session == null) return const SignOutRefused(signOutSessionChangedMessage);
      final serverUrl = session.serverUrl;
      final serverId = ServerRegistryStore.entryIdFromUrl(serverUrl);

      ServerEntry? entry;
      var removed = false;
      String? notice;
      try {
        final registry = await loadRegistry();
        entry = ServerRegistryStore.findByUrl(registry, serverUrl);
        if (removeServer) {
          await saveRegistry(ServerRegistryStore.removeServer(registry, serverId));
          removed = true;
        }
      } catch (_) {
        // Signing out still goes ahead: it lands on the server's sign-in
        // screen, which says the server is still saved.
        if (removeServer) notice = removeServerFailedMessage;
      }

      try {
        await clearSession();
      } catch (_) {
        return const SignOutRefused(signOutLocalFailedMessage);
      }

      final name = entry?.fetchedName.trim() ?? '';
      return SignedOut(
        serverUrl: serverUrl,
        removedServer: removed,
        serverName: name.isEmpty ? null : name,
        username: session.username.isEmpty ? null : session.username,
        notice: notice,
      );
    } finally {
      _running = false;
    }
  }
}

final signOutRunnerProvider = Provider<SignOutRunner>((ref) => SignOutRunner());
