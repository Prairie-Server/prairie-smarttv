import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors LiveTvPlayerScreen.tsx: tunes a channel, plays its stream, and
/// always releases the tuner session on exit (including if the user leaves
/// mid-tune).
class LiveTvPlayerScreen extends ConsumerStatefulWidget {
  const LiveTvPlayerScreen({super.key, required this.channel, required this.back});

  final LiveTvChannel channel;
  final Route back;

  @override
  ConsumerState<LiveTvPlayerScreen> createState() => _LiveTvPlayerScreenState();
}

class _LiveTvPlayerScreenState extends ConsumerState<LiveTvPlayerScreen> {
  VideoBackend? _backend;
  String? _liveSessionId;
  bool _loading = true;
  String? _error;
  String? _note;
  bool _exited = false;

  @override
  void initState() {
    super.initState();
    _tune();
  }

  @override
  void dispose() {
    // Mirrors the effect cleanup releasing a session that resolved after
    // the user already navigated away.
    if (!_exited && _liveSessionId != null) {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      unawaited(releaseLiveTvSession(client, session, _liveSessionId!).catchError((_) {}));
    }
    _backend?.dispose();
    super.dispose();
  }

  Future<void> _tune() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final started = await startLiveTvSession(client, session, widget.channel.id);
      if (!mounted || _exited) {
        await releaseLiveTvSession(client, session, started.sessionId).catchError((_) {});
        return;
      }
      _liveSessionId = started.sessionId;
      final raw = playableLiveUrl(started);
      if (raw == null) throw StateError('Live TV session returned no stream URL');
      final streamUrl = resolveLivePlaybackUrl(session.serverUrl, raw, session.accessToken, session.profileId);
      final caps = ref.read(tvCapabilitiesProvider);
      final backend = ref.read(videoBackendFactoryProvider)();
      backend.attach(streamUrl, maxResolution: caps.maxResolution);
      // Mount hole-punch surface before initialize (same as VOD PlayerScreen).
      setState(() {
        _backend = backend;
        _note = started.note;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _exited) {
        await backend.dispose();
        await releaseLiveTvSession(client, session, started.sessionId).catchError((_) {});
        _liveSessionId = null;
        return;
      }
      await backend.initialize();
      await backend.play();
      if (!mounted || _exited) {
        await backend.dispose();
        await releaseLiveTvSession(client, session, started.sessionId).catchError((_) {});
        _liveSessionId = null;
        return;
      }
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiError ? e.message : 'Could not start Live TV';
          _loading = false;
        });
      }
    }
  }

  Future<void> _exit() async {
    if (_exited) return;
    _exited = true;
    final sessionId = _liveSessionId;
    _liveSessionId = null;
    final backend = _backend;
    _backend = null;
    await backend?.dispose();
    if (sessionId != null) {
      final session = ref.read(sessionProvider);
      if (session != null) {
        await releaseLiveTvSession(ref.read(apiClientProvider), session, sessionId).catchError((_) {});
      }
    }
    if (!mounted) return;
    ref.read(routeProvider.notifier).go(widget.back);
  }

  Future<void> _togglePlayPause() async {
    final backend = _backend;
    if (backend == null) return;
    if (backend.isPlaying) {
      await backend.pause();
    } else {
      await backend.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final backend = _backend;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (backend != null) Center(child: backend.buildSurface()),
            if (_loading) const Center(child: PrairieLoadingIndicator()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LIVE TV', style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600, letterSpacing: 2)),
                      Text(channelDisplayLabel(widget.channel), style: const TextStyle(fontFamily: 'Fraunces', fontSize: 24, color: PrairieColors.ink)),
                      Text(
                        'Ch ${widget.channel.numberOverride ?? widget.channel.number}${widget.channel.hd ? ' · HD' : ''}${_loading ? ' · tuning…' : ' · live'}${_note != null ? ' · $_note' : ''}',
                        style: const TextStyle(color: PrairieColors.muted),
                      ),
                      const SizedBox(height: 12),
                      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: PrairieColors.danger))),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            autofocus: true,
                            onPressed: backend == null || _error != null ? null : _togglePlayPause,
                            icon: Icon(backend?.isPlaying ?? false ? Icons.pause : Icons.play_arrow),
                            label: Text(backend?.isPlaying ?? false ? 'Pause' : 'Play'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(onPressed: _exit, icon: const Icon(Icons.stop), label: const Text('Stop')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Live sessions are released when you leave this screen', style: TextStyle(color: PrairieColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
