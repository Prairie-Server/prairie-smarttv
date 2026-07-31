import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/auth.dart';
import '../platform/client_identity.dart';
import '../storage/durable_store.dart';
import '../storage/server_registry_store.dart';
import '../storage/session_store.dart';

final sharedPreferencesProvider = Provider<SharedPreferencesAsync>((ref) => SharedPreferencesAsync());

final durableStoreProvider = Provider<DurableStore>((ref) {
  return DurableStore(prefs: ref.watch(sharedPreferencesProvider));
});

final sessionStoreProvider = Provider<SessionStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SessionStore(prefs: prefs, durable: ref.watch(durableStoreProvider));
});

final serverRegistryStoreProvider = Provider<ServerRegistryStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ServerRegistryStore(
    prefs: prefs,
    durable: ref.watch(durableStoreProvider),
    sessionStore: ref.watch(sessionStoreProvider),
  );
});

/// Platform apps override with Tizen/webOS-specific User-Agent + device labels.
final clientIdentityProvider = Provider<ClientIdentity>((ref) => const ClientIdentity());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(identity: ref.watch(clientIdentityProvider));
});

/// Holds the active [PrairieSession], if any. Mirrors the `session` useState
/// in src/App.tsx, including registry / last-URL cold-start fallback.
class SessionNotifier extends Notifier<PrairieSession?> {
  @override
  PrairieSession? build() => null;

  /// Boot path: ensure durable schema, migrate legacy registry, then restore
  /// session — falling back to an active registry entry when present.
  Future<void> restore() async {
    final durable = ref.read(durableStoreProvider);
    await durable.ensureStorageSchema();
    final registryStore = ref.read(serverRegistryStoreProvider);
    await registryStore.migrateFromLegacy();

    final session = await ref.read(sessionStoreProvider).load();
    if (session != null) {
      state = session;
      return;
    }

    final fromRegistry = await registryStore.sessionFromActive();
    if (fromRegistry != null) {
      state = await ref.read(sessionStoreProvider).save(fromRegistry);
      return;
    }

    state = null;
  }

  Future<void> set(PrairieSession session, {String fetchedName = ''}) async {
    final saved = await ref.read(sessionStoreProvider).save(session);
    final registryStore = ref.read(serverRegistryStoreProvider);
    final next = ServerRegistryStore.rememberSession(
      await registryStore.load(),
      saved,
      fetchedName: fetchedName,
    );
    await registryStore.save(next);
    state = saved;
  }

  Future<void> clear() async {
    final registryStore = ref.read(serverRegistryStoreProvider);
    final registry = await registryStore.load();
    if (registry.activeServerId.isNotEmpty) {
      await registryStore.save(ServerRegistryStore.clearTokens(registry, registry.activeServerId));
    }
    await ref.read(sessionStoreProvider).clear();
    state = null;
  }

  void updateTokens(String accessToken, String? refreshToken) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(accessToken: accessToken, refreshToken: refreshToken);
    unawaited(ref.read(sessionStoreProvider).save(state!));
  }

  /// Last known server URL (survives logout) for Connect pre-fill / cold start.
  Future<String> lastServerUrl() => ref.read(durableStoreProvider).loadLastServerUrl();
}

final sessionProvider = NotifierProvider<SessionNotifier, PrairieSession?>(SessionNotifier.new);
