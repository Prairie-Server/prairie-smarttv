import 'dart:io';

import '../api/api_client.dart';
import '../api/health_api.dart';
import '../models/server_entry.dart';

/// Native Prairie liveness + identity path. Mirrors src/discovery/discover.ts.
const healthPath = '/api/v1/health';

/// Prairie default listen is :8080. Extra ports cover reverse-proxy/TLS setups.
const List<int> defaultPorts = [8080, 8443, 443, 80];

/// Deep LAN sweeps use a single port so a /24 finishes in reasonable time.
const List<int> deepScanPorts = [8080];

/// Same fallback prefixes Litefin uses when the NIC /24 is unknown or empty.
const List<String> commonCidrs = ['192.168.0.0/24', '192.168.1.0/24', '10.0.0.0/24'];

const List<int> _priorityLastOctets = [1, 2, 10, 20, 50, 100, 150, 200, 254];

List<int>? ipv4Parts(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  final nums = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    nums.add(value);
  }
  return nums;
}

String formatIpv4(List<int> parts) => '${parts[0]}.${parts[1]}.${parts[2]}.${parts[3]}';

({List<int> network, int prefix})? parseCidr(String cidr) {
  final trimmed = cidr.trim();
  final slash = trimmed.indexOf('/');
  if (slash < 0) return null;
  final ip = trimmed.substring(0, slash);
  final prefix = int.tryParse(trimmed.substring(slash + 1));
  if (prefix == null || prefix < 24 || prefix > 32) return null;
  final parts = ipv4Parts(ip);
  if (parts == null) return null;
  return (network: parts, prefix: prefix);
}

String subnetCidrForIp(String ip) {
  final parts = ipv4Parts(ip);
  if (parts == null) return '';
  return '${parts[0]}.${parts[1]}.${parts[2]}.0/24';
}

void _pushUnique(List<String> list, Set<String> seen, String value) {
  final key = value.toLowerCase();
  if (seen.contains(key)) return;
  seen.add(key);
  list.add(value);
}

void urlsForHost(String host, List<int> ports, Set<String> seen, List<String> out) {
  for (final port in ports) {
    if (port == 443) {
      _pushUnique(out, seen, 'https://$host');
    } else if (port == 80) {
      _pushUnique(out, seen, 'http://$host');
    } else {
      _pushUnique(out, seen, 'http://$host:$port');
      if (port == 8443) _pushUnique(out, seen, 'https://$host:$port');
    }
  }
}

List<String> priorityHostsForSubnet(List<int> base) =>
    _priorityLastOctets.map((last) => formatIpv4([base[0], base[1], base[2], last])).toList();

List<String> allHostsForCidr(({List<int> network, int prefix}) parsed, [int maxHosts = 254]) {
  final hosts = <String>[];
  final bits = 32 - parsed.prefix;
  if (bits == 0) {
    hosts.add(formatIpv4(parsed.network));
    return hosts;
  }
  final count = 1 << bits;
  var startOffset = 1;
  var endOffset = count - 2;
  if (endOffset < startOffset) {
    startOffset = 0;
    endOffset = count - 1;
  }
  var added = 0;
  for (var offset = startOffset; offset <= endOffset; offset++) {
    if (added >= maxHosts) break;
    if (parsed.prefix < 24) break;
    final last = parsed.network[3] + offset;
    if (last > 255) break;
    hosts.add(formatIpv4([parsed.network[0], parsed.network[1], parsed.network[2], last]));
    added++;
  }
  return hosts;
}

List<String> collectScanCidrs({List<String> extraCidrs = const [], List<String> localIps = const []}) {
  final cidrs = <String>[];
  final seen = <String>{};
  for (final ip in localIps) {
    final cidr = subnetCidrForIp(ip);
    if (cidr.isNotEmpty) _pushUnique(cidrs, seen, cidr);
  }
  for (final cidr in commonCidrs) {
    _pushUnique(cidrs, seen, cidr);
  }
  for (final cidr in extraCidrs) {
    final trimmed = cidr.trim();
    if (trimmed.isNotEmpty) _pushUnique(cidrs, seen, trimmed);
  }
  return cidrs;
}

/// Mirrors `buildCandidates` from discover.ts: prairie.local/prairie first,
/// then local NIC /24 + common private ranges (+ optional extras), priority
/// hosts by default or a full /24 sweep when [deepScan] is true.
List<String> buildCandidates({
  List<String> extraCidrs = const [],
  bool deepScan = false,
  int maxHostsPerCidr = 254,
  List<String> localIps = const [],
  List<String>? baseHosts,
}) {
  final out = <String>[];
  final seen = <String>{};

  final hostsToProbe = (baseHosts != null && baseHosts.isNotEmpty) ? baseHosts : const ['prairie.local', 'prairie'];
  for (final host in hostsToProbe) {
    urlsForHost(host, defaultPorts, seen, out);
  }
  for (final ip in localIps) {
    if (ipv4Parts(ip) != null) urlsForHost(ip, defaultPorts, seen, out);
  }

  final cidrs = collectScanCidrs(extraCidrs: extraCidrs, localIps: localIps);
  final hostPorts = deepScan ? deepScanPorts : defaultPorts;

  for (final cidr in cidrs) {
    final parsed = parseCidr(cidr);
    if (parsed == null) continue;
    final hosts = deepScan ? allHostsForCidr(parsed, maxHostsPerCidr) : priorityHostsForSubnet(parsed.network);
    for (final host in hosts) {
      urlsForHost(host, hostPorts, seen, out);
    }
  }

  return out;
}

/// Best-effort local IPv4 discovery. Unlike the TS version — which relies on
/// a Tizen-only `webapis.network.getIp()` and returns nothing on webOS or in
/// a plain browser — a native Flutter app has real OS networking APIs, so
/// this reads actual NIC addresses via `dart:io` on every platform.
Future<List<String>> localIpv4Addresses() async {
  final ips = <String>[];
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (!ips.contains(addr.address)) ips.add(addr.address);
      }
    }
  } catch (_) {
    // Best-effort — fall back to commonCidrs-only scanning.
  }
  return ips;
}

List<DiscoveryHit> mergeHits(List<DiscoveryHit> hits, String url, HealthIdentity health) {
  final idx = hits.indexWhere((h) => h.url == url);
  if (idx >= 0) {
    final existing = hits[idx];
    hits[idx] = DiscoveryHit(
      url: existing.url,
      serverName: health.serverName.isNotEmpty ? health.serverName : existing.serverName,
      serverId: health.serverId.isNotEmpty ? health.serverId : existing.serverId,
    );
    return hits;
  }
  hits.add(DiscoveryHit(url: url, serverName: health.serverName, serverId: health.serverId));
  return hits;
}

/// Probes [candidates] concurrently (bounded batches, matching the LAN-scan
/// spirit of the TS app without blocking the UI thread on hundreds of
/// sequential requests) and returns servers that responded healthy.
///
/// Not a direct TS port (there's no single `scanForServers` in discover.ts —
/// that orchestration lived in ServerListScreen.tsx, which isn't ported
/// yet); this is the equivalent entry point for the Flutter ServersScreen.
Future<List<DiscoveryHit>> scanForServers(
  ApiClient client,
  List<String> candidates, {
  int concurrency = 24,
}) async {
  var hits = <DiscoveryHit>[];
  for (var i = 0; i < candidates.length; i += concurrency) {
    final batch = candidates.skip(i).take(concurrency);
    final results = await Future.wait(
      batch.map((url) async {
        final health = await fetchServerHealth(client, url);
        return (url: url, health: health);
      }),
    );
    for (final result in results) {
      if (result.health != null) {
        hits = mergeHits(hits, result.url, result.health!);
      }
    }
  }
  return hits;
}
