import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors the "servers" route in src/App.tsx / ServerListScreen.tsx: LAN
/// scan for nearby Prairie servers, plus manual entry.
///
/// The saved-server registry (src/storage/serverRegistry.ts, multiple
/// remembered servers with quick reconnect) isn't ported yet — this only
/// covers the discovery + manual-entry half of that screen.
class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key, this.autoScan = true});

  final bool autoScan;

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  bool _scanning = false;
  List<DiscoveryHit> _hits = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoScan) _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final localIps = await localIpv4Addresses();
      final candidates = buildCandidates(localIps: localIps);
      final hits = await scanForServers(client, candidates);
      if (!mounted) return;
      setState(() => _hits = hits);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _selectHit(DiscoveryHit hit) {
    ref.read(routeProvider.notifier).openLogin(hit.url, serverName: hit.serverName.isNotEmpty ? hit.serverName : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('SERVERS', style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  const Text('Find your Prairie server', style: TextStyle(fontFamily: 'Fraunces', fontSize: 32, color: PrairieColors.ink)),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _scanning ? null : _scan,
                        icon: _scanning
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_find),
                        label: Text(_scanning ? 'Scanning your network…' : 'Scan again'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        autofocus: true,
                        onPressed: () => ref.read(routeProvider.notifier).go(const ManualServerRoute()),
                        icon: const Icon(Icons.add),
                        label: const Text('Add server manually'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
                  Flexible(
                    child: _hits.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              _scanning ? 'Looking for servers on your network…' : 'No servers found yet',
                              style: const TextStyle(color: PrairieColors.muted),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final hit in _hits)
                                Card(
                                  color: PrairieColors.bgElevated,
                                  child: ListTile(
                                    leading: const Icon(Icons.dns, color: PrairieColors.amber),
                                    title: Text(
                                      hit.serverName.isNotEmpty ? hit.serverName : hit.url,
                                      style: const TextStyle(color: PrairieColors.ink),
                                    ),
                                    subtitle: Text(hit.url, style: const TextStyle(color: PrairieColors.muted)),
                                    onTap: () => _selectHit(hit),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
