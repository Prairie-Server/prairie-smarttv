import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _progressIntervalMs = 10000;
/// HLS remux/transcode sessions that stop advancing for this long after play
/// started are treated as a dead encode (ffmpeg exit) rather than forever-buffer.
const _hlsStallTimeout = Duration(seconds: 20);

/// Mirrors PlayerScreen.tsx's playback session lifecycle (start/progress
/// heartbeat/stop), transport controls, and subtitle track/appearance.
///
/// Audio track switching still isn't native — Prairie restarts the stream
/// via PATCH `/playback/{id}/audio` (same as the TS client).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.launch, required this.back});

  final PlayerLaunch launch;
  final Route back;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoBackend? _backend;
  PlaybackSessionResponse? _playbackSession;
  /// Tracked as soon as `/playback/start` returns so Back during prepare
  /// still DELETEs the server session (PlusPlayer can open the stream before
  /// Dart finishes initialize).
  String? _activeSessionId;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<String?>? _captionSub;
  StreamSubscription<String>? _errorSub;
  Duration _position = Duration.zero;
  Duration _lastProgressPosition = Duration.zero;
  DateTime? _lastProgressAt;
  bool _loading = true;
  String? _error;
  bool _controlsVisible = true;
  Timer? _progressTimer;
  Timer? _hideControlsTimer;
  Timer? _stallTimer;
  bool _exiting = false;
  SubtitleAppearance _subtitleAppearance = const SubtitleAppearance();
  int? _selectedSubtitleTrackId;
  String? _caption;
  CancelToken? _prepareCancel;
  bool _busyAudio = false;

  @override
  void initState() {
    super.initState();
    _start();
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _prepareCancel?.cancel();
    _positionSub?.cancel();
    _captionSub?.cancel();
    _errorSub?.cancel();
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _stallTimer?.cancel();
    // Widget teardown that bypasses [_exit] (route replace, error boundary)
    // must still stop the Prairie session and free the hardware decoder.
    final sessionId = _activeSessionId;
    _activeSessionId = null;
    if (sessionId != null && !_exiting) {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider);
      if (session != null) {
        unawaited(stopPlaybackSession(client, session, sessionId).catchError((_) {}));
      }
    }
    final backend = _backend;
    _backend = null;
    if (backend != null) {
      unawaited(backend.dispose());
    }
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  String? _sourceResolutionForFile(WatchDetail? detail, int fileId) {
    if (detail == null) return null;
    for (final version in detail.versions) {
      if (version.fileId == fileId) return version.resolution;
    }
    return detail.versions.isNotEmpty ? detail.versions.first.resolution : null;
  }

  List<AudioTrackInfo> get _audioTracks {
    final watch = widget.launch.watch;
    final fileId = _playbackSession?.mediaFileId ?? widget.launch.fileId;
    if (watch == null) return const [];
    final version = selectFileVersion(watch, fileId);
    return version?.audioTracks ?? const [];
  }

  Future<void> _chooseAudio(int index) async {
    final current = _playbackSession;
    final sessionId = _activeSessionId ?? current?.sessionId;
    if (current == null || sessionId == null || _busyAudio || _exiting) return;
    if (index == current.audioTrackIndex) return;

    setState(() {
      _busyAudio = true;
      _error = null;
      _loading = true;
    });

    final cancel = CancelToken();
    _prepareCancel?.cancel();
    _prepareCancel = cancel;

    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final settings = await loadPlaybackSettings(SharedPreferencesAsync());
      final deviceCaps = applyAv1AdvertiseOverrides(
        ref.read(tvCapabilitiesProvider),
        forceAv1: settings.forceAv1,
        disableAv1: settings.disableAv1,
      );

      final position = _position.inMilliseconds / 1000.0;
      final updated = await switchPlaybackAudio(client, session, sessionId, index, position);
      if (!mounted || _exiting || cancel.isCancelled) return;

      final nextSession = PlaybackSessionResponse(
        sessionId: current.sessionId,
        mediaFileId: current.mediaFileId,
        playMethod: updated.playMethod.isNotEmpty ? updated.playMethod : current.playMethod,
        position: position,
        isPaused: current.isPaused,
        streamUrl: updated.streamUrl.isNotEmpty ? updated.streamUrl : current.streamUrl,
        audioTrackIndex: updated.audioTrackIndex,
        durationSeconds: current.durationSeconds,
        playbackInfo: updated.playbackInfo ?? current.playbackInfo,
      );

      final prepared = await preparePlayableSession(
        client,
        session,
        nextSession,
        position,
        sourceResolution: _sourceResolutionForFile(widget.launch.watch, nextSession.mediaFileId),
        maxResolution: deviceCaps.maxResolution,
        cancelToken: cancel,
      );
      if (!mounted || _exiting || cancel.isCancelled) {
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        return;
      }

      _activeSessionId = prepared.session.sessionId;
      await _positionSub?.cancel();
      await _captionSub?.cancel();
      await _errorSub?.cancel();
      _stallTimer?.cancel();
      final oldBackend = _backend;
      _backend = null;
      await oldBackend?.dispose();

      final backend = ref.read(videoBackendFactoryProvider)();
      backend.attach(prepared.streamUrl, maxResolution: deviceCaps.maxResolution);
      setState(() {
        _backend = backend;
        _playbackSession = prepared.session;
        _position = Duration(milliseconds: (prepared.playerStartSeconds * 1000).round());
        _selectedSubtitleTrackId = null;
        _caption = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _exiting || cancel.isCancelled) {
        await backend.dispose();
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        return;
      }

      await backend.initialize(
        startPosition: prepared.playerStartSeconds > 0
            ? Duration(milliseconds: (prepared.playerStartSeconds * 1000).round())
            : null,
      );
      await backend.play();
      if (!mounted || _exiting || cancel.isCancelled) {
        await backend.dispose();
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        return;
      }

      setState(() {
        _loading = false;
        _busyAudio = false;
      });
      _lastProgressPosition = _position;
      _lastProgressAt = DateTime.now();
      _positionSub = backend.positionStream.listen((pos) {
        if (!mounted) return;
        if (pos != _lastProgressPosition) {
          _lastProgressPosition = pos;
          _lastProgressAt = DateTime.now();
        }
        setState(() => _position = pos);
      });
      _captionSub = backend.captionStream.listen((text) {
        if (mounted) setState(() => _caption = text);
      });
      _errorSub = backend.errorStream.listen((message) {
        if (!mounted || _exiting || _error != null) return;
        setState(() {
          _error = message;
          _loading = false;
        });
      });
      if (needsHlsBootstrap(prepared.session.playMethod)) {
        _stallTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkHlsStall());
      }
      unawaited(_autoSelectSubtitleTrack(backend, settings.preferredSubtitleLanguage));
      _showControls();
    } catch (e) {
      if (mounted && !_exiting) {
        setState(() {
          _error = e is ApiError ? e.message : 'Could not switch audio';
          _loading = false;
          _busyAudio = false;
        });
      }
    }
  }

  Future<void> _pickAudioTrack() async {
    final tracks = _audioTracks;
    if (tracks.isEmpty) return;
    final currentIndex = _playbackSession?.audioTrackIndex ?? 0;
    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: PrairieColors.bgElevated,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tracks.length; i++)
              ListTile(
                title: Text(formatAudioLabel(tracks[i], i), style: const TextStyle(color: PrairieColors.ink)),
                trailing: i == currentIndex ? const Icon(Icons.check, color: PrairieColors.amber) : null,
                onTap: () => Navigator.of(context).pop<int>(i),
              ),
          ],
        ),
      ),
    );
    if (choice == null || choice == currentIndex) return;
    await _chooseAudio(choice);
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final cancel = CancelToken();
    _prepareCancel?.cancel();
    _prepareCancel = cancel;

    String? startedSessionId;
    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final settings = await loadPlaybackSettings(SharedPreferencesAsync());
      final deviceCaps = applyAv1AdvertiseOverrides(
        ref.read(tvCapabilitiesProvider),
        forceAv1: settings.forceAv1,
        disableAv1: settings.disableAv1,
      );
      final forcedMethod = switch (resolveForcedPlayMethod(settings)) {
        'direct' => PlayMethod.direct,
        'transcode' => PlayMethod.transcode,
        _ => null,
      };

      final started = await startPlayback(
        client,
        session,
        BuildPlaybackStartInput(
          fileId: widget.launch.fileId,
          profileId: session.profileId,
          startPosition: widget.launch.startPositionSeconds,
          forcedPlayMethod: forcedMethod,
          codecsVideo: deviceCaps.codecsVideo,
          codecsAudio: deviceCaps.codecsAudio,
          containers: deviceCaps.containers,
          maxResolution: deviceCaps.maxResolution,
          hdr: deviceCaps.hdr,
        ),
      );
      startedSessionId = started.sessionId;
      _activeSessionId = started.sessionId;

      if (!mounted || _exiting || cancel.isCancelled) {
        await stopPlaybackSession(client, session, started.sessionId).catchError((_) {});
        _activeSessionId = null;
        return;
      }

      final seekAt = widget.launch.startPositionSeconds ?? started.position;
      final PreparedPlayback prepared;
      try {
        prepared = await preparePlayableSession(
          client,
          session,
          started,
          seekAt,
          sourceResolution: _sourceResolutionForFile(widget.launch.watch, started.mediaFileId),
          maxResolution: deviceCaps.maxResolution,
          cancelToken: cancel,
        );
      } catch (prepErr) {
        await stopPlaybackSession(client, session, started.sessionId).catchError((_) {});
        _activeSessionId = null;
        rethrow;
      }

      if (!mounted || _exiting || cancel.isCancelled) {
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _activeSessionId = null;
        return;
      }

      _activeSessionId = prepared.session.sessionId;
      final backend = ref.read(videoBackendFactoryProvider)();
      backend.attach(prepared.streamUrl, maxResolution: deviceCaps.maxResolution);
      // Mount the hole-punch surface BEFORE initialize — PlusPlayer prepares
      // against the display rect; awaiting init with no VideoPlayer in the
      // tree leaves Direct Play streaming on the server while Flutter spins.
      setState(() {
        _backend = backend;
        _playbackSession = prepared.session;
        _subtitleAppearance = settings.subtitleAppearance;
        _position = Duration(milliseconds: (prepared.playerStartSeconds * 1000).round());
      });
      await WidgetsBinding.instance.endOfFrame;

      if (!mounted || _exiting || cancel.isCancelled) {
        await backend.dispose();
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _activeSessionId = null;
        return;
      }

      await backend.initialize(
        startPosition: prepared.playerStartSeconds > 0
            ? Duration(milliseconds: (prepared.playerStartSeconds * 1000).round())
            : null,
      );
      await backend.play();

      if (!mounted || _exiting || cancel.isCancelled) {
        await backend.dispose();
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _activeSessionId = null;
        return;
      }

      setState(() => _loading = false);
      _lastProgressPosition = _position;
      _lastProgressAt = DateTime.now();
      _positionSub = backend.positionStream.listen((position) {
        if (!mounted) return;
        if (position != _lastProgressPosition) {
          _lastProgressPosition = position;
          _lastProgressAt = DateTime.now();
        }
        setState(() => _position = position);
      });
      _captionSub = backend.captionStream.listen((text) {
        if (mounted) setState(() => _caption = text);
      });
      _errorSub = backend.errorStream.listen((message) {
        if (!mounted || _exiting || _error != null) return;
        setState(() {
          _error = message;
          _loading = false;
        });
      });
      _progressTimer = Timer.periodic(const Duration(milliseconds: _progressIntervalMs), (_) => _reportProgress());
      if (needsHlsBootstrap(prepared.session.playMethod)) {
        _stallTimer?.cancel();
        _stallTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkHlsStall());
      }
      unawaited(_autoSelectSubtitleTrack(backend, settings.preferredSubtitleLanguage));
    } catch (e) {
      if (startedSessionId != null && _activeSessionId == startedSessionId) {
        // Leave stop to the catch path only when we didn't already stop above.
      }
      if (mounted && !_exiting) {
        setState(() {
          _error = e is ApiError
              ? e.message
              : e is TranscodeStartupTimeoutError
                  ? e.message
                  : 'Playback failed: $e';
          _loading = false;
        });
      }
    }
  }

  void _checkHlsStall() {
    if (!mounted || _exiting || _error != null || _loading) return;
    final backend = _backend;
    if (backend == null || !backend.isPlaying) return;
    final lastAt = _lastProgressAt;
    if (lastAt == null) return;
    if (DateTime.now().difference(lastAt) < _hlsStallTimeout) return;
    setState(() {
      _error = 'Playback stalled — the stream stopped producing media.';
      _loading = false;
    });
    _stallTimer?.cancel();
  }

  /// Mirrors `resolvePreferredSubtitleIndex`: auto-select a text track
  /// whose language matches the viewer's saved preference, if any.
  Future<void> _autoSelectSubtitleTrack(VideoBackend backend, String preferredLanguage) async {
    if (preferredLanguage.isEmpty) return;
    for (final track in backend.subtitleTracks) {
      if (track.language.toLowerCase() == preferredLanguage) {
        await backend.selectSubtitleTrack(track.trackId);
        if (mounted) setState(() => _selectedSubtitleTrackId = track.trackId);
        return;
      }
    }
  }

  Future<void> _pickSubtitleTrack() async {
    final backend = _backend;
    if (backend == null) return;
    final choice = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: PrairieColors.bgElevated,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Off', style: TextStyle(color: PrairieColors.ink)),
              trailing: _selectedSubtitleTrackId == null ? const Icon(Icons.check, color: PrairieColors.amber) : null,
              onTap: () => Navigator.of(context).pop<int?>(null),
            ),
            for (final track in backend.subtitleTracks)
              ListTile(
                title: Text(track.language, style: const TextStyle(color: PrairieColors.ink)),
                trailing: _selectedSubtitleTrackId == track.trackId ? const Icon(Icons.check, color: PrairieColors.amber) : null,
                onTap: () => Navigator.of(context).pop<int?>(track.trackId),
              ),
          ],
        ),
      ),
    );
    if (choice == _selectedSubtitleTrackId) return;
    await backend.selectSubtitleTrack(choice);
    if (mounted) {
      setState(() {
        _selectedSubtitleTrackId = choice;
        if (choice == null) _caption = null;
      });
    }
  }

  Future<void> _reportProgress({bool paused = false}) async {
    final sessionId = _activeSessionId ?? _playbackSession?.sessionId;
    if (sessionId == null) return;
    try {
      await reportPlaybackProgress(
        ref.read(apiClientProvider),
        ref.read(sessionProvider)!,
        sessionId,
        _position.inSeconds.toDouble(),
        paused,
      );
    } catch (_) {
      // Best-effort — a missed heartbeat isn't worth surfacing to the viewer.
    }
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    _prepareCancel?.cancel();
    final backend = _backend;
    _backend = null;
    final sessionId = _activeSessionId ?? _playbackSession?.sessionId;
    _activeSessionId = null;
    _playbackSession = null;
    _progressTimer?.cancel();
    _stallTimer?.cancel();
    await _errorSub?.cancel();
    _errorSub = null;
    if (sessionId != null) {
      await _reportProgress(paused: true);
      // Await stop so Back cannot race a new play against a still-open session
      // on the single hardware decoder / server encode slot.
      final session = ref.read(sessionProvider);
      if (session != null) {
        await stopPlaybackSession(ref.read(apiClientProvider), session, sessionId).catchError((_) {});
      }
    }
    await backend?.dispose();
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
    _showControls();
    setState(() {});
  }

  Future<void> _seekBy(Duration delta) async {
    final backend = _backend;
    if (backend == null) return;
    final duration = backend.duration ?? Duration.zero;
    var next = _position + delta;
    if (next < Duration.zero) next = Duration.zero;
    if (duration > Duration.zero && next > duration) next = duration;
    await backend.seekTo(next);
    setState(() => _position = next);
    _showControls();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
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
        body: GestureDetector(
          onTap: _showControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backend != null) backend.buildSurface(),
              if (_caption != null && _caption!.isNotEmpty)
                Align(
                  alignment: Alignment(0, 1 - 2 * subtitleAppearanceBottomFraction(_subtitleAppearance)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: subtitleAppearanceBackgroundColor(_subtitleAppearance),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Text(_caption!, textAlign: TextAlign.center, style: subtitleAppearanceTextStyle(_subtitleAppearance)),
                      ),
                    ),
                  ),
                ),
              if (_loading) const Center(child: CircularProgressIndicator(color: PrairieColors.amber)),
              if (_error != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: PrairieColors.danger)),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _exit, child: const Text('Back')),
                    ],
                  ),
                ),
              if (_controlsVisible && backend != null && !_loading && _error == null)
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
                        children: [
                          Text(widget.launch.title ?? '', style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, color: PrairieColors.ink)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(_formatDuration(_position), style: const TextStyle(color: PrairieColors.muted)),
                              Expanded(
                                child: Slider(
                                  value: _position.inMilliseconds.toDouble().clamp(0, (backend.duration ?? const Duration(seconds: 1)).inMilliseconds.toDouble()),
                                  max: (backend.duration ?? const Duration(seconds: 1)).inMilliseconds.toDouble().clamp(1, double.infinity),
                                  activeColor: PrairieColors.amber,
                                  onChanged: (value) => setState(() => _position = Duration(milliseconds: value.round())),
                                  onChangeEnd: (value) => backend.seekTo(Duration(milliseconds: value.round())),
                                ),
                              ),
                              Text(_formatDuration(backend.duration ?? Duration.zero), style: const TextStyle(color: PrairieColors.muted)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(iconSize: 32, color: PrairieColors.ink, onPressed: _exit, icon: const Icon(Icons.close)),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () => _seekBy(const Duration(seconds: -15)),
                                child: const Text('-15s', style: TextStyle(color: PrairieColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                iconSize: 48,
                                color: PrairieColors.amber,
                                onPressed: _togglePlayPause,
                                icon: Icon(backend.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => _seekBy(const Duration(seconds: 15)),
                                child: const Text('+15s', style: TextStyle(color: PrairieColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
                              ),
                              if (_audioTracks.length > 1) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  iconSize: 28,
                                  color: _busyAudio ? PrairieColors.muted : PrairieColors.ink,
                                  onPressed: _busyAudio ? null : _pickAudioTrack,
                                  icon: const Icon(Icons.audiotrack),
                                  tooltip: 'Audio',
                                ),
                              ],
                              if (backend.subtitleTracks.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  iconSize: 28,
                                  color: _selectedSubtitleTrackId != null ? PrairieColors.amber : PrairieColors.ink,
                                  onPressed: _pickSubtitleTrack,
                                  icon: const Icon(Icons.closed_caption),
                                  tooltip: 'Subtitles',
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
