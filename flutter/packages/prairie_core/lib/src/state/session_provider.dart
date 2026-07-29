import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/auth.dart';
import '../storage/session_store.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Holds the active [PrairieSession], if any. Mirrors the `session`
/// useState in src/App.tsx, minus the localStorage-registry fallback (no
/// multi-server registry ported yet — single active session for now).
class SessionNotifier extends Notifier<PrairieSession?> {
  @override
  PrairieSession? build() => null;

  Future<void> restore() async {
    state = await ref.read(sessionStoreProvider).load();
  }

  Future<void> set(PrairieSession session) async {
    state = await ref.read(sessionStoreProvider).save(session);
  }

  Future<void> clear() async {
    await ref.read(sessionStoreProvider).clear();
    state = null;
  }

  void updateTokens(String accessToken, String? refreshToken) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(accessToken: accessToken, refreshToken: refreshToken);
    unawaited(ref.read(sessionStoreProvider).save(state!));
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, PrairieSession?>(SessionNotifier.new);
