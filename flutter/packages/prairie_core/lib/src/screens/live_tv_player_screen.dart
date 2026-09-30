import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart' show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the live picture is actually doing, as opposed to what the player
/// was last told to do: `play()` resolving only means the native player
/// accepted the call, and a live stream can sit on its first frame (or
/// freeze mid-stream) for seconds while it buffers.
enum LiveTvPlaybackStatus { tuning, starting, live, buffering, paused, failed }

/// How long the position may stand still while playing before the picture
/// counts as stalled. The backend samples position about once a second, so
/// this has to allow for a couple of missed ticks.
const liveTvStallThreshold = Duration(milliseconds: 2500);

LiveTvPlaybackStatus liveTvPlaybackStatus({
  required bool tuning,
  required bool failed,
  required bool isPlaying,
  required bool isBuffering,
  required bool hasAdvanced,
  required Duration sinceLastAdvance,
}) {
  if (failed) return LiveTvPlaybackStatus.failed;
  if (tuning) return LiveTvPlaybackStatus.tuning;
  if (!isPlaying) return LiveTvPlaybackStatus.paused;
  if (!hasAdvanced) return LiveTvPlaybackStatus.starting;
  if (isBuffering || sinceLastAdvance > liveTvStallThreshold) return LiveTvPlaybackStatus.buffering;
  return LiveTvPlaybackStatus.live;
}

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
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _heartbeat;
  Timer? _statusTimer;
  Timer? _hideControlsTimer;
  bool _controlsVisible = true;
  Duration? _lastPosition;
  DateTime? _lastAdvanceAt;
  bool _hasAdvanced = false;
  LiveTvPlaybackStatus _status = LiveTvPlaybackStatus.tuning;

  /// Receives D-pad keys while chrome is hidden so any key can bring it back.
  final FocusNode _idleFocus = FocusNode(debugLabel: 'live.idle');
  final FocusNode _playFocus = FocusNode(debugLabel: 'live.play');

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
    _heartbeat?.cancel();
    _statusTimer?.cancel();
    _hideControlsTimer?.cancel();
    _errorSub?.cancel();
    _positionSub?.cancel();
    _idleFocus.dispose();
    _playFocus.dispose();
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
      _startHeartbeat(started.sessionId);
      final raw = playableLiveUrl(started);
      if (raw == null) throw StateError('Live TV session returned no stream URL');
      // Re-read: the tune above may have refreshed the access token, and the
      // native player cannot refresh one on its own.
      final fresh = ref.read(sessionProvider) ?? session;
      final streamUrl = resolveLivePlaybackUrl(fresh.serverUrl, raw, fresh.accessToken, fresh.profileId);
      final caps = ref.read(tvCapabilitiesProvider);
      final settings = await loadPlaybackSettings(SharedPreferencesAsync());
      final backend = ref.read(videoBackendFactoryProvider)(enableDiagnostics: settings.enableDiagnosticsBeacon);
      backend.attach(streamUrl, maxResolution: caps.maxResolution);
      // The native player reports failures asynchronously (after initialize
      // resolves, or mid-stream); show them instead of a silent black screen.
      await _errorSub?.cancel();
      _errorSub = backend.errorStream.listen((message) {
        if (!mounted) return;
        setState(() => _error = message);
        _refreshStatus();
      });
      await _positionSub?.cancel();
      _positionSub = backend.positionStream.listen(_onPosition);
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
      // Only a position that moves proves the picture is live; until then the
      // status stays "starting" and the spinner stays up.
      _statusTimer?.cancel();
      _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _refreshStatus());
      _refreshStatus();
    } catch (e) {
      if (mounted) {
        setState(() {
          // Keep the real cause visible: a generic message hid whether the
          // tune, the native player's initialize, or play() failed.
          _error = e is ApiError ? e.message : 'Could not start Live TV: ${e is PlatformException ? (e.message ?? e.code) : e}';
          _loading = false;
        });
        _refreshStatus();
      }
    }
  }

  void _onPosition(Duration position) {
    final last = _lastPosition;
    _lastPosition = position;
    if (last == null || position == last) return;
    _lastAdvanceAt = DateTime.now();
    _hasAdvanced = true;
  }

  void _refreshStatus() {
    if (!mounted) return;
    final backend = _backend;
    final lastAdvance = _lastAdvanceAt;
    final next = liveTvPlaybackStatus(
      tuning: _loading,
      failed: _error != null,
      isPlaying: backend?.isPlaying ?? false,
      isBuffering: backend?.isBuffering ?? false,
      hasAdvanced: _hasAdvanced,
      sinceLastAdvance: lastAdvance == null ? Duration.zero : DateTime.now().difference(lastAdvance),
    );
    if (next == _status) return;
    setState(() => _status = next);
    if (next == LiveTvPlaybackStatus.live) {
      _scheduleHideControls();
    } else if (next != LiveTvPlaybackStatus.buffering) {
      // Tuning, paused and failed need the chrome (and its status) on screen;
      // a mid-stream stall only needs the spinner.
      _hideControlsTimer?.cancel();
      if (!_controlsVisible) _showControls();
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_status != LiveTvPlaybackStatus.live) return;
    _hideControlsTimer = Timer(const Duration(seconds: 5), _hideControlsNow);
  }

  void _hideControlsNow() {
    if (!mounted) return;
    _hideControlsTimer?.cancel();
    setState(() => _controlsVisible = false);
    // The buttons leave the tree with their focus nodes; park focus on the
    // idle catcher so the next remote key has somewhere to land.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_controlsVisible) _idleFocus.requestFocus();
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controlsVisible) _playFocus.requestFocus();
    });
  }

  /// Any remote key while chrome is hidden re-shows it; Back still bubbles to
  /// [PopScope]. While chrome is up, any key restarts the hide countdown.
  KeyEventResult _onIdleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_controlsVisible) {
      _scheduleHideControls();
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.browserBack) {
      return KeyEventResult.ignored;
    }
    _showControls();
    return KeyEventResult.handled;
  }

  /// Keeps the tuner claimed while this screen is open (paused included):
  /// one heartbeat now, then every [liveTvHeartbeatInterval]. Failures are
  /// ignored like web's, except a 404 — the session is gone, so stop.
  void _startHeartbeat(String sessionId) {
    _heartbeat?.cancel();
    Future<void> send() async {
      final session = ref.read(sessionProvider);
      if (!mounted || _exited || session == null || _liveSessionId != sessionId) return;
      try {
        await heartbeatLiveTvSession(ref.read(apiClientProvider), session, sessionId);
      } on ApiError catch (err) {
        if (err.status == 404) _heartbeat?.cancel();
      } catch (_) {
        // Best effort; the next tick retries.
      }
    }

    unawaited(send());
    _heartbeat = Timer.periodic(liveTvHeartbeatInterval, (_) => unawaited(send()));
  }

  Future<void> _exit() async {
    if (_exited) return;
    _exited = true;
    _heartbeat?.cancel();
    _statusTimer?.cancel();
    _hideControlsTimer?.cancel();
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
      // No position tick arrives while paused, so without this the resumed
      // stream would read as stalled before it has had a chance to advance.
      _lastAdvanceAt = DateTime.now();
    }
    if (!mounted) return;
    setState(() {});
    _refreshStatus();
  }

  Widget _buildStatusPill() {
    final (label, color) = switch (_status) {
      LiveTvPlaybackStatus.tuning => ('Tuning…', PrairieColors.amber),
      LiveTvPlaybackStatus.starting => ('Starting…', PrairieColors.amber),
      LiveTvPlaybackStatus.buffering => ('Buffering…', PrairieColors.amber),
      LiveTvPlaybackStatus.live => ('LIVE', PrairieColors.danger),
      LiveTvPlaybackStatus.paused => ('Paused', PrairieColors.muted),
      LiveTvPlaybackStatus.failed => ('Error', PrairieColors.danger),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_status == LiveTvPlaybackStatus.live) ...[
              DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const SizedBox(width: 10, height: 10),
              ),
              const SizedBox(width: 8),
            ],
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backend = _backend;
    final waiting = switch (_status) {
      LiveTvPlaybackStatus.tuning || LiveTvPlaybackStatus.starting || LiveTvPlaybackStatus.buffering => true,
      _ => false,
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Same as the VOD player: the first Back dismisses the chrome, and only
        // a Back with the chrome already hidden leaves the channel.
        if (_controlsVisible && _status == LiveTvPlaybackStatus.live) {
          _hideControlsNow();
        } else {
          _exit();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _idleFocus,
          skipTraversal: true,
          onKeyEvent: _onIdleKey,
          child: GestureDetector(
            onTap: _showControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backend != null) Center(child: backend.buildSurface()),
                if (waiting) const Center(child: PrairieLoadingIndicator()),
                if (_controlsVisible)
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
                            Row(
                              children: [
                                _buildStatusPill(),
                                const SizedBox(width: 12),
                                Text('LIVE TV', style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600, letterSpacing: 2)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(channelDisplayLabel(widget.channel), style: const TextStyle(fontFamily: 'Fraunces', fontSize: 24, color: PrairieColors.ink)),
                            Text(
                              'Ch ${widget.channel.numberOverride ?? widget.channel.number}${widget.channel.hd ? ' · HD' : ''}${_note != null ? ' · $_note' : ''}',
                              style: const TextStyle(color: PrairieColors.muted),
                            ),
                            const SizedBox(height: 12),
                            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: PrairieColors.danger))),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  focusNode: _playFocus,
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
        ),
      ),
    );
  }
}
