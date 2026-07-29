import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth.dart';
import '../models/server_entry.dart';
import 'durable_store.dart';
import 'session_store.dart';

/// Multi-server registry persistence. Mirrors `src/storage/serverRegistry.ts`.
///
/// Token material is never written to SharedPreferences — only identity /
/// metadata. Active session tokens live in [SessionStore] (secure storage).
class ServerRegistryStore {
  ServerRegistryStore({SharedPreferencesAsync? prefs, DurableStore? durable, SessionStore? sessionStore})
    : _prefs = prefs ?? SharedPreferencesAsync(),
      _durable = durable,
      _sessionStore = sessionStore;

  final SharedPreferencesAsync _prefs;
  final DurableStore? _durable;
  final SessionStore? _sessionStore;

  DurableStore get _d => _durable ?? DurableStore(prefs: _prefs);

  /// Stable client-derived ID: base64url of the normalized URL.
  static String entryIdFromUrl(String url) {
    final normalized = DurableStore.normalizeServerUrl(url);
    if (normalized.isEmpty) return '';
    return base64Url.encode(utf8.encode(normalized)).replaceAll('=', '');
  }

  static ServerEntry? normalizeEntry(Map<String, dynamic>? entry) {
    if (entry == null) return null;
    final rawUrl = entry['url'] as String?;
    final url = rawUrl != null ? DurableStore.normalizeServerUrl(rawUrl) : '';
    if (url.isEmpty) return null;
    final idRaw = (entry['id'] as String?)?.trim();
    final id = (idRaw != null && idRaw.isNotEmpty) ? idRaw : entryIdFromUrl(url);
    return ServerEntry(
      id: id,
      url: url,
      fetchedName: entry['fetchedName'] as String? ?? '',
      username: entry['username'] as String? ?? '',
      profileId: entry['profileId'] as String? ?? '',
      profileName: entry['profileName'] as String? ?? '',
      // Token material must never persist in SharedPreferences.
      accessToken: '',
      profileToken: '',
      lastUsedAt: entry['lastUsedAt'] is num ? (entry['lastUsedAt'] as num).toInt() : 0,
    );
  }

  static ServerEntry? normalizeServerEntry(ServerEntry? entry) {
    if (entry == null) return null;
    final url = DurableStore.normalizeServerUrl(entry.url);
    if (url.isEmpty) return null;
    final id = entry.id.trim().isNotEmpty ? entry.id : entryIdFromUrl(url);
    return ServerEntry(
      id: id,
      url: url,
      fetchedName: entry.fetchedName,
      username: entry.username,
      profileId: entry.profileId,
      profileName: entry.profileName,
      accessToken: entry.accessToken,
      profileToken: entry.profileToken,
      lastUsedAt: entry.lastUsedAt,
    );
  }

  static String displayName(ServerEntry entry) {
    final name = entry.fetchedName.trim();
    return name.isNotEmpty ? name : entry.url;
  }

  Future<ServerRegistry> load() async {
    final registry = ServerRegistry.empty();
    var hadPersistedTokens = false;
    try {
      final raw = await _prefs.getString(DurableStore.serverRegistryKey);
      if (raw == null || raw.trim().isEmpty) return registry;
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final active = parsed['activeServerId'];
      final activeServerId = active is String ? active : '';
      final entries = <ServerEntry>[];
      final rawEntries = parsed['entries'];
      if (rawEntries is List) {
        for (final entry in rawEntries) {
          if (entry is! Map) continue;
          final map = Map<String, dynamic>.from(entry);
          // Detect legacy token material before normalize strips it.
          if ((map['accessToken'] as String?)?.isNotEmpty == true ||
              (map['profileToken'] as String?)?.isNotEmpty == true) {
            hadPersistedTokens = true;
          }
          final normalized = normalizeEntry(map);
          if (normalized != null) entries.add(normalized);
        }
      }
      final scanCidrs = <String>[];
      final rawCidrs = parsed['scanCidrs'];
      if (rawCidrs is List) {
        for (final cidr in rawCidrs) {
          if (cidr is String && cidr.trim().isNotEmpty) scanCidrs.add(cidr.trim());
        }
      }
      final loaded = ServerRegistry(
        activeServerId: activeServerId,
        entries: entries,
        scanCidrs: scanCidrs,
      );
      if (hadPersistedTokens) {
        await save(loaded);
      }
      return loaded;
    } catch (_) {
      return ServerRegistry.empty();
    }
  }

  Future<void> save(ServerRegistry registry) async {
    final entriesJson = <Map<String, dynamic>>[];
    for (final entry in registry.entries) {
      final n = normalizeServerEntry(entry);
      if (n == null) continue;
      entriesJson.add({
        'id': n.id,
        'url': n.url,
        'fetchedName': n.fetchedName,
        'username': n.username,
        'profileId': n.profileId,
        'profileName': n.profileName,
        // Never persist token material.
        'accessToken': '',
        'profileToken': '',
        'lastUsedAt': n.lastUsedAt,
      });
    }
    final payload = {
      'activeServerId': registry.activeServerId,
      'entries': entriesJson,
      'scanCidrs': List<String>.from(registry.scanCidrs),
    };
    await _prefs.setString(DurableStore.serverRegistryKey, jsonEncode(payload));
  }

  static int findIndex(ServerRegistry registry, String serverId) =>
      registry.entries.indexWhere((e) => e.id == serverId);

  static ServerEntry? findByUrl(ServerRegistry registry, String url) {
    final idx = findIndex(registry, entryIdFromUrl(url));
    return idx < 0 ? null : registry.entries[idx];
  }

  static List<ServerEntry> sortedEntries(ServerRegistry registry) {
    final activeId = registry.activeServerId;
    final copy = List<ServerEntry>.from(registry.entries);
    copy.sort((a, b) {
      if (a.id == activeId && b.id != activeId) return -1;
      if (b.id == activeId && a.id != activeId) return 1;
      return b.lastUsedAt.compareTo(a.lastUsedAt);
    });
    return copy;
  }

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static ServerRegistry addOrUpdate(ServerRegistry registry, ServerEntry entry) {
    final normalized = normalizeServerEntry(entry);
    if (normalized == null) return registry;
    final entries = List<ServerEntry>.from(registry.entries);
    final idx = findIndex(registry, normalized.id);
    if (idx >= 0) {
      final existing = entries[idx];
      entries[idx] = ServerEntry(
        id: normalized.id,
        url: normalized.url,
        fetchedName: normalized.fetchedName.isNotEmpty ? normalized.fetchedName : existing.fetchedName,
        username: normalized.username.isNotEmpty ? normalized.username : existing.username,
        profileId: normalized.profileId.isNotEmpty ? normalized.profileId : existing.profileId,
        profileName: normalized.profileName.isNotEmpty ? normalized.profileName : existing.profileName,
        accessToken: normalized.accessToken.isNotEmpty ? normalized.accessToken : existing.accessToken,
        profileToken: normalized.profileToken.isNotEmpty ? normalized.profileToken : existing.profileToken,
        lastUsedAt: normalized.lastUsedAt != 0 ? normalized.lastUsedAt : existing.lastUsedAt,
      );
    } else {
      entries.add(
        ServerEntry(
          id: normalized.id,
          url: normalized.url,
          fetchedName: normalized.fetchedName,
          username: normalized.username,
          profileId: normalized.profileId,
          profileName: normalized.profileName,
          accessToken: normalized.accessToken,
          profileToken: normalized.profileToken,
          lastUsedAt: normalized.lastUsedAt != 0 ? normalized.lastUsedAt : _nowSeconds(),
        ),
      );
    }
    return ServerRegistry(
      activeServerId: registry.activeServerId,
      entries: entries,
      scanCidrs: registry.scanCidrs,
    );
  }

  static ServerRegistry removeServer(ServerRegistry registry, String serverId) {
    final entries = List<ServerEntry>.from(registry.entries)..removeWhere((e) => e.id == serverId);
    var active = registry.activeServerId;
    if (active == serverId) {
      active = '';
      if (entries.isNotEmpty) {
        active = sortedEntries(
          ServerRegistry(activeServerId: '', entries: entries, scanCidrs: registry.scanCidrs),
        ).first.id;
      }
    }
    return ServerRegistry(activeServerId: active, entries: entries, scanCidrs: registry.scanCidrs);
  }

  static ServerRegistry switchTo(ServerRegistry registry, String serverId) {
    final idx = findIndex(registry, serverId);
    if (idx < 0) return registry;
    final entries = List<ServerEntry>.from(registry.entries);
    final e = entries[idx];
    entries[idx] = ServerEntry(
      id: e.id,
      url: e.url,
      fetchedName: e.fetchedName,
      username: e.username,
      profileId: e.profileId,
      profileName: e.profileName,
      accessToken: e.accessToken,
      profileToken: e.profileToken,
      lastUsedAt: _nowSeconds(),
    );
    return ServerRegistry(activeServerId: serverId, entries: entries, scanCidrs: registry.scanCidrs);
  }

  static ServerRegistry rememberSession(
    ServerRegistry registry,
    PrairieSession session, {
    String fetchedName = '',
  }) {
    final next = addOrUpdate(
      registry,
      ServerEntry(
        id: entryIdFromUrl(session.serverUrl),
        url: session.serverUrl,
        fetchedName: fetchedName,
        username: session.username,
        profileId: session.profileId,
        profileName: session.profileName ?? '',
        accessToken: session.accessToken,
        profileToken: session.profileToken ?? '',
        lastUsedAt: _nowSeconds(),
      ),
    );
    return ServerRegistry(
      activeServerId: entryIdFromUrl(session.serverUrl),
      entries: next.entries,
      scanCidrs: next.scanCidrs,
    );
  }

  static PrairieSession? sessionFromEntry(ServerEntry? entry) {
    if (entry == null) return null;
    if (entry.accessToken.isEmpty || entry.profileId.isEmpty || entry.username.isEmpty) {
      return null;
    }
    return PrairieSession(
      serverUrl: entry.url,
      accessToken: entry.accessToken,
      username: entry.username,
      profileId: entry.profileId,
      profileName: entry.profileName.isNotEmpty ? entry.profileName : null,
      profileToken: entry.profileToken.isNotEmpty ? entry.profileToken : null,
    );
  }

  static ServerRegistry clearTokens(ServerRegistry registry, String serverId) {
    final idx = findIndex(registry, serverId);
    if (idx < 0) return registry;
    final entries = List<ServerEntry>.from(registry.entries);
    final e = entries[idx];
    entries[idx] = ServerEntry(
      id: e.id,
      url: e.url,
      fetchedName: e.fetchedName,
      username: e.username,
      profileId: e.profileId,
      profileName: e.profileName,
      accessToken: '',
      profileToken: '',
      lastUsedAt: e.lastUsedAt,
    );
    return ServerRegistry(
      activeServerId: registry.activeServerId,
      entries: entries,
      scanCidrs: registry.scanCidrs,
    );
  }

  /// Promote legacy single lastServerUrl/session into the registry (schema v2).
  Future<ServerRegistry> migrateFromLegacy() async {
    final registry = await load();
    if (registry.entries.isNotEmpty) return registry;

    final session = await (_sessionStore ?? SessionStore(prefs: _prefs)).load();
    final lastUrl = await _d.loadLastServerUrl();
    var next = registry;
    if (session != null) {
      next = rememberSession(next, session);
    } else if (lastUrl.isNotEmpty) {
      next = addOrUpdate(
        next,
        ServerEntry(
          id: entryIdFromUrl(lastUrl),
          url: lastUrl,
          fetchedName: '',
          username: '',
          profileId: '',
          profileName: '',
          accessToken: '',
          profileToken: '',
          lastUsedAt: _nowSeconds(),
        ),
      );
      next = ServerRegistry(
        activeServerId: entryIdFromUrl(lastUrl),
        entries: next.entries,
        scanCidrs: next.scanCidrs,
      );
    }
    if (next.entries.isNotEmpty) {
      await save(next);
    }
    return next;
  }

  /// Best-effort session from the active registry entry (needs in-memory tokens).
  Future<PrairieSession?> sessionFromActive() async {
    final registry = await load();
    if (registry.activeServerId.isEmpty) return null;
    final idx = findIndex(registry, registry.activeServerId);
    if (idx < 0) return null;
    return sessionFromEntry(registry.entries[idx]);
  }
}
