import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth.dart';
import 'durable_store.dart';

/// Persists the active [PrairieSession]: identity in [SharedPreferencesAsync]
/// (non-secret — server URL, username, profile), tokens in
/// [FlutterSecureStorage].
///
/// Mirrors src/storage/session.ts, with one deliberate upgrade: tokens go in
/// secure storage rather than plaintext. The TS version used plaintext
/// localStorage only because packaged WebViews tear down sessionStorage on
/// exit; a native Flutter app has no such WebView, so there's no reason not
/// to use the platform keystore. Legacy sessionStorage migration has no
/// Flutter equivalent and is dropped.
///
/// [clear] removes session identity + tokens but does **not** remove
/// [DurableStore.lastServerUrlKey], the server registry, or playback settings
/// — those must survive logout and app upgrades.
class SessionStore {
  SessionStore({SharedPreferencesAsync? prefs, FlutterSecureStorage? secureStorage, DurableStore? durable})
    : _prefs = prefs ?? SharedPreferencesAsync(),
      _secure = secureStorage ?? const FlutterSecureStorage(),
      _durable = durable;

  final SharedPreferencesAsync _prefs;
  final FlutterSecureStorage _secure;
  final DurableStore? _durable;

  DurableStore get _d => _durable ?? DurableStore(prefs: _prefs);

  static const _serverUrlKey = 'prairie.session.serverUrl';
  static const _usernameKey = 'prairie.session.username';
  static const _profileIdKey = 'prairie.session.profileId';
  static const _profileNameKey = 'prairie.session.profileName';
  static const _profileAvatarUrlKey = 'prairie.session.profileAvatarUrl';
  static const _accessTokenKey = 'prairie.session.accessToken';
  static const _refreshTokenKey = 'prairie.session.refreshToken';
  static const _profileTokenKey = 'prairie.session.profileToken';

  Future<PrairieSession?> load() async {
    final serverUrl = await _prefs.getString(_serverUrlKey);
    final username = await _prefs.getString(_usernameKey);
    final profileId = await _prefs.getString(_profileIdKey);
    if (serverUrl == null || username == null || profileId == null) return null;

    final accessToken = await _secure.read(key: _accessTokenKey);
    if (accessToken == null) return null;

    return PrairieSession(
      serverUrl: serverUrl,
      username: username,
      profileId: profileId,
      profileName: await _prefs.getString(_profileNameKey),
      profileAvatarUrl: await _prefs.getString(_profileAvatarUrlKey),
      accessToken: accessToken,
      refreshToken: await _secure.read(key: _refreshTokenKey),
      profileToken: await _secure.read(key: _profileTokenKey),
    );
  }

  Future<PrairieSession> save(PrairieSession session) async {
    final normalizedUrl = DurableStore.normalizeServerUrl(session.serverUrl);
    await _prefs.setString(_serverUrlKey, normalizedUrl);
    await _prefs.setString(_usernameKey, session.username);
    await _prefs.setString(_profileIdKey, session.profileId);
    if (session.profileName != null) {
      await _prefs.setString(_profileNameKey, session.profileName!);
    } else {
      await _prefs.remove(_profileNameKey);
    }
    if (session.profileAvatarUrl != null) {
      await _prefs.setString(_profileAvatarUrlKey, session.profileAvatarUrl!);
    } else {
      await _prefs.remove(_profileAvatarUrlKey);
    }

    await _secure.write(key: _accessTokenKey, value: session.accessToken);
    if (session.refreshToken != null) {
      await _secure.write(key: _refreshTokenKey, value: session.refreshToken);
    } else {
      await _secure.delete(key: _refreshTokenKey);
    }
    if (session.profileToken != null) {
      await _secure.write(key: _profileTokenKey, value: session.profileToken);
    } else {
      await _secure.delete(key: _profileTokenKey);
    }

    // Keep last server URL even if the user later disconnects (pre-fill Connect).
    await _d.saveLastServerUrl(normalizedUrl);
    return session.copyWith(serverUrl: normalizedUrl);
  }

  /// Updates access/refresh tokens after a successful refresh without
  /// rewriting profile identity. Mirrors `updateSessionTokens`.
  Future<PrairieSession?> updateTokens({required String accessToken, String? refreshToken}) async {
    final current = await load();
    if (current == null) return null;
    return save(current.copyWith(accessToken: accessToken, refreshToken: refreshToken));
  }

  /// Clears the active session tokens. Does NOT remove lastServerUrl,
  /// registry, or playback settings.
  Future<void> clear() async {
    await _prefs.remove(_serverUrlKey);
    await _prefs.remove(_usernameKey);
    await _prefs.remove(_profileIdKey);
    await _prefs.remove(_profileNameKey);
    await _prefs.remove(_profileAvatarUrlKey);
    await _secure.delete(key: _accessTokenKey);
    await _secure.delete(key: _refreshTokenKey);
    await _secure.delete(key: _profileTokenKey);
  }
}
