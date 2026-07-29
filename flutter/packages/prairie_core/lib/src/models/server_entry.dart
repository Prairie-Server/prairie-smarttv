/// Mirrors `ServerEntry` from src/storage/serverRegistry.ts.
class ServerEntry {
  const ServerEntry({
    required this.id,
    required this.url,
    required this.fetchedName,
    required this.username,
    required this.profileId,
    required this.profileName,
    required this.accessToken,
    required this.profileToken,
    required this.lastUsedAt,
  });

  final String id;
  final String url;
  final String fetchedName;
  final String username;
  final String profileId;
  final String profileName;
  final String accessToken;
  final String profileToken;
  final int lastUsedAt;
}

/// Mirrors `ServerRegistry` from src/storage/serverRegistry.ts.
class ServerRegistry {
  const ServerRegistry({
    required this.activeServerId,
    required this.entries,
    required this.scanCidrs,
  });

  factory ServerRegistry.empty() =>
      const ServerRegistry(activeServerId: '', entries: [], scanCidrs: []);

  final String activeServerId;
  final List<ServerEntry> entries;
  final List<String> scanCidrs;
}

/// Mirrors `DiscoveryHit` from src/discovery/discover.ts.
class DiscoveryHit {
  const DiscoveryHit({required this.url, required this.serverName, required this.serverId});

  final String url;
  final String serverName;
  final String serverId;
}
