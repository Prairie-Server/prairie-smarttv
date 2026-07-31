import 'package:shared_preferences/shared_preferences.dart';

/// Cross-upgrade persistence helpers.
///
/// Mirrors `src/storage/persist.ts`. Identity rules (do not break without a
/// migration):
/// - SharedPreferences keys stay on the `prairie.*` prefix
/// - Schema bumps must be additive. Never clear session or settings keys on
///   upgrade.
///
/// Tokens live in [FlutterSecureStorage] (see [SessionStore]); non-secret
/// durable keys live here in SharedPreferences, which survives app updates.
class DurableStore {
  DurableStore({SharedPreferencesAsync? prefs}) : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const storageSchemaKey = 'prairie.storageSchemaVersion';

  /// Bump only when additive migrations are required. Never wipe on bump.
  static const storageSchemaVersion = 2;

  static const lastServerUrlKey = 'prairie.lastServerUrl';
  static const playbackSettingsKey = 'prairie.playbackSettings';

  /// Pre-Flutter / early Flutter key — migrated into [playbackSettingsKey].
  static const legacyPlaybackSettingsKey = 'prairie.settings.playback';
  static const serverRegistryKey = 'prairie.serverRegistry';
  static const performanceModeKey = 'prairie.performanceMode';

  /// Keys that must survive app updates. Cleared only by explicit user logout
  /// of *session* material — registry / last URL / settings stay.
  static const preservedStorageKeys = [
    lastServerUrlKey,
    serverRegistryKey,
    playbackSettingsKey,
    storageSchemaKey,
    performanceModeKey,
  ];

  SharedPreferencesAsync get prefs => _prefs;

  static String normalizeServerUrl(String url) => url.trim().replaceFirst(RegExp(r'/+$'), '');

  Future<String> loadLastServerUrl() async {
    try {
      final direct = await _prefs.getString(lastServerUrlKey);
      if (direct != null && direct.trim().isNotEmpty) {
        return normalizeServerUrl(direct);
      }
      // Flutter stores session identity as discrete keys (not a JSON blob).
      final sessionUrl = await _prefs.getString('prairie.session.serverUrl');
      return sessionUrl != null ? normalizeServerUrl(sessionUrl) : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> saveLastServerUrl(String url) async {
    final normalized = normalizeServerUrl(url);
    if (normalized.isNotEmpty) {
      await _prefs.setString(lastServerUrlKey, normalized);
    }
  }

  /// Ensure schema version is recorded. Migrations may copy/rename keys but
  /// must not remove [preservedStorageKeys]. Safe to call on every boot.
  Future<int> ensureStorageSchema() async {
    var current = 0;
    try {
      final raw = await _prefs.getString(storageSchemaKey);
      current = raw != null ? (int.tryParse(raw) ?? 0) : 0;
    } catch (_) {
      // keep current at 0 when storage is unavailable
    }

    // v0 → v1: promote server URL out of the session so Connect still
    // pre-fills after a partial/corrupt session without wiping tokens.
    if (current < 1) {
      try {
        final existing = await _prefs.getString(lastServerUrlKey);
        if (existing == null || existing.isEmpty) {
          final sessionUrl = await _prefs.getString('prairie.session.serverUrl');
          if (sessionUrl != null && sessionUrl.isNotEmpty) {
            await _prefs.setString(lastServerUrlKey, normalizeServerUrl(sessionUrl));
          }
        }
      } catch (_) {
        /* leave keys untouched */
      }
      await _prefs.setString(storageSchemaKey, '1');
      current = 1;
    }

    // v1 → v2: registry key introduced. Migration of session/last URL into
    // prairie.serverRegistry is performed by ServerRegistryStore.migrateFromLegacy
    // on boot (avoids a store ↔ registry import cycle at call sites).
    // Also migrate legacy playback settings key.
    if (current < 2) {
      await _migratePlaybackSettingsKey();
      await _prefs.setString(storageSchemaKey, '$storageSchemaVersion');
      return storageSchemaVersion;
    }

    // Always attempt legacy playback key migration (idempotent) in case a
    // device was already on schema 2 before this helper existed.
    await _migratePlaybackSettingsKey();
    return current;
  }

  Future<void> _migratePlaybackSettingsKey() async {
    try {
      final modern = await _prefs.getString(playbackSettingsKey);
      if (modern != null && modern.isNotEmpty) return;
      final legacy = await _prefs.getString(legacyPlaybackSettingsKey);
      if (legacy == null || legacy.isEmpty) return;
      await _prefs.setString(playbackSettingsKey, legacy);
    } catch (_) {
      /* leave keys untouched */
    }
  }
}
