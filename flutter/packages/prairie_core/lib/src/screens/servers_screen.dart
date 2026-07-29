import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ServerListScreen.tsx: saved-server registry, LAN discovery, and
/// manual entry.
class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key, this.autoScan = true});

  final bool autoScan;

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  bool _scanning = false;
  bool _connecting = false;
  List<DiscoveryHit> _hits = [];
  List<ServerEntry> _saved = [];
  String? _activeServerId;
  String? _selectedId;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _reloadRegistry();
    if (!widget.autoScan) return;
    // Prefer saved servers — skip LAN discovery until the user asks to scan.
    if (_saved.isNotEmpty) {
      setState(() => _status = 'Select a saved server, or scan to find others nearby.');
      return;
    }
    await _scan();
  }

  Future<void> _reloadRegistry() async {
    final store = ref.read(serverRegistryStoreProvider);
    final registry = await store.load();
    if (!mounted) return;
    setState(() {
      _saved = ServerRegistryStore.sortedEntries(registry);
      _activeServerId = registry.activeServerId;
    });
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _hits = [];
      _status = 'Looking for Prairie servers on your network…';
    });
    try {
      final client = ref.read(apiClientProvider);
      final localIps = await localIpv4Addresses();
      final candidates = buildCandidates(localIps: localIps);
      final hits = await scanForServers(client, candidates);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _status = hits.isEmpty
            ? 'No Prairie servers found — add one manually or scan again'
            : 'Found ${hits.length} server(s)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _removeSelected() async {
    final id = _selectedId;
    if (id == null || _connecting) return;
    final store = ref.read(serverRegistryStoreProvider);
    final next = ServerRegistryStore.removeServer(await store.load(), id);
    await store.save(next);
    if (!mounted) return;
    setState(() => _selectedId = null);
    await _reloadRegistry();
  }

  Future<void> _selectSaved(ServerEntry entry) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
      _status = 'Connecting to ${ServerRegistryStore.displayName(entry)}…';
    });
    try {
      final store = ref.read(serverRegistryStoreProvider);
      var registry = await store.load();
      final idx = ServerRegistryStore.findIndex(registry, entry.id);
      if (idx < 0) return;
      final full = registry.entries[idx];
      registry = ServerRegistryStore.switchTo(registry, full.id);
      await store.save(registry);

      final restored = ServerRegistryStore.sessionFromEntry(full);
      if (restored != null) {
        await ref.read(sessionProvider.notifier).set(restored, fetchedName: full.fetchedName);
        if (!mounted) return;
        ref.read(routeProvider.notifier).go(const HomeRoute());
        return;
      }

      final probe = await checkServer(ref.read(apiClientProvider), full.url);
      if (probe is CheckServerFailure) throw StateError(probe.message);
      final ok = probe as CheckServerSuccess;
      if (ok.needsSetup) {
        throw StateError(
          'This server has not been set up yet. Open its web UI in a browser on another '
          'device to create the first account, then return here to sign in.',
        );
      }

      if (ok.serverName != null &&
          ok.serverName!.trim().isNotEmpty &&
          ok.serverName!.trim() != full.fetchedName.trim()) {
        registry = ServerRegistryStore.addOrUpdate(
          registry,
          ServerEntry(
            id: full.id,
            url: ok.serverUrl,
            fetchedName: ok.serverName!.trim(),
            username: full.username,
            profileId: full.profileId,
            profileName: full.profileName,
            accessToken: '',
            profileToken: '',
            lastUsedAt: full.lastUsedAt,
          ),
        );
        await store.save(registry);
      }

      if (!mounted) return;
      ref.read(routeProvider.notifier).openLogin(
        ok.serverUrl,
        serverName: ok.serverName?.trim().isNotEmpty == true ? ok.serverName!.trim() : full.fetchedName,
        initialUsername: full.username.isNotEmpty ? full.username : null,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is StateError ? e.message : '$e';
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _selectHit(DiscoveryHit hit) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
      _status = 'Connecting to ${hit.serverName.trim().isNotEmpty ? hit.serverName : hit.url}…';
    });
    try {
      final store = ref.read(serverRegistryStoreProvider);
      if (hit.serverName.trim().isNotEmpty) {
        final registry = ServerRegistryStore.addOrUpdate(
          await store.load(),
          ServerEntry(
            id: ServerRegistryStore.entryIdFromUrl(hit.url),
            url: hit.url,
            fetchedName: hit.serverName,
            username: '',
            profileId: '',
            profileName: '',
            accessToken: '',
            profileToken: '',
            lastUsedAt: 0,
          ),
        );
        await store.save(registry);
      }

      final probe = await checkServer(ref.read(apiClientProvider), hit.url);
      if (probe is CheckServerFailure) throw StateError(probe.message);
      final ok = probe as CheckServerSuccess;
      if (ok.needsSetup) {
        throw StateError(
          'This server has not been set up yet. Open its web UI in a browser on another '
          'device to create the first account, then return here to sign in.',
        );
      }

      if (ok.serverName != null && ok.serverName!.trim().isNotEmpty) {
        final registry = ServerRegistryStore.addOrUpdate(
          await store.load(),
          ServerEntry(
            id: ServerRegistryStore.entryIdFromUrl(ok.serverUrl),
            url: ok.serverUrl,
            fetchedName: ok.serverName!.trim(),
            username: '',
            profileId: '',
            profileName: '',
            accessToken: '',
            profileToken: '',
            lastUsedAt: 0,
          ),
        );
        await store.save(registry);
      }

      if (!mounted) return;
      ref.read(routeProvider.notifier).openLogin(
        ok.serverUrl,
        serverName: ok.serverName?.trim().isNotEmpty == true
            ? ok.serverName!.trim()
            : (hit.serverName.trim().isNotEmpty ? hit.serverName.trim() : null),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is StateError ? e.message : '$e';
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedUrls = _saved.map((e) => e.url).toSet();
    final freshHits = _hits.where((h) => !savedUrls.contains(h.url)).toList();
    final controlsLocked = _connecting;

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
                  Text(
                    'SERVERS',
                    style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600, letterSpacing: 2),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Prairie',
                    style: TextStyle(fontFamily: 'Fraunces', fontSize: 32, color: PrairieColors.ink),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a saved server, one found nearby, or add an address.',
                    style: TextStyle(color: PrairieColors.muted),
                  ),
                  const SizedBox(height: 24),
                  if (_status != null) ...[
                    Text(_status!, style: const TextStyle(color: PrairieColors.muted)),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (_scanning || _connecting) ? null : _scan,
                        icon: _scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_find),
                        label: Text(_scanning ? 'Scanning…' : _connecting ? 'Connecting…' : 'Scan again'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        autofocus: _saved.isEmpty,
                        onPressed: controlsLocked
                            ? null
                            : () => ref.read(routeProvider.notifier).go(const ManualServerRoute()),
                        icon: const Icon(Icons.add),
                        label: const Text('Add manually'),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: controlsLocked || _selectedId == null ? null : _removeSelected,
                        icon: const Icon(Icons.delete_outline, color: PrairieColors.muted),
                        label: const Text('Remove', style: TextStyle(color: PrairieColors.muted)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (_saved.isNotEmpty) ...[
                          const Text('Saved', style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          for (var i = 0; i < _saved.length; i++)
                            Card(
                              color: PrairieColors.bgElevated,
                              child: ListTile(
                                autofocus: i == 0,
                                selected: _saved[i].id == _selectedId,
                                leading: const Icon(Icons.dns, color: PrairieColors.amber),
                                title: Text(
                                  ServerRegistryStore.displayName(_saved[i]),
                                  style: const TextStyle(color: PrairieColors.ink),
                                ),
                                subtitle: Text(
                                  '${_saved[i].id == _activeServerId ? 'Active · ' : 'Saved · '}'
                                  '${_saved[i].username.isNotEmpty ? '${_saved[i].username} · ' : ''}'
                                  '${_saved[i].url}',
                                  style: const TextStyle(color: PrairieColors.muted),
                                ),
                                onFocusChange: (focused) {
                                  if (focused) setState(() => _selectedId = _saved[i].id);
                                },
                                onTap: controlsLocked ? null : () => _selectSaved(_saved[i]),
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],
                        if (freshHits.isNotEmpty || _scanning) ...[
                          const Text(
                            'Discovered',
                            style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          for (final hit in freshHits)
                            Card(
                              color: PrairieColors.bgElevated,
                              child: ListTile(
                                leading: const Icon(Icons.wifi_tethering, color: PrairieColors.amber),
                                title: Text(
                                  hit.serverName.isNotEmpty ? hit.serverName : hit.url,
                                  style: const TextStyle(color: PrairieColors.ink),
                                ),
                                subtitle: Text('Found · ${hit.url}', style: const TextStyle(color: PrairieColors.muted)),
                                onTap: controlsLocked ? null : () => _selectHit(hit),
                              ),
                            ),
                          if (_scanning && freshHits.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'Scanning your network for Prairie…',
                                style: TextStyle(color: PrairieColors.muted),
                              ),
                            ),
                        ],
                        if (!_scanning && _saved.isEmpty && freshHits.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              'No servers yet — wait for the scan, or add a URL manually.',
                              style: TextStyle(color: PrairieColors.muted),
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
