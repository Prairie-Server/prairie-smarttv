import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _progressIntervalMs = 10000;

/// Mirrors PlayerScreen.tsx's playback session lifecycle (start/progress
/// heartbeat/stop), transport controls, and subtitle track/appearance.
///
/// Audio track switching still isn't wired up — [VideoBackend] doesn't
/// expose audio tracks yet, only text tracks.
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
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<String?>? _captionSub;
  Duration _position = Duration.zero;
  bool _loading = true;
  String? _error;
  bool _controlsVisible = true;
  Timer? _progressTimer;
  Timer? _hideControlsTimer;
  bool _exiting = false;
  SubtitleAppearance _subtitleAppearance = const SubtitleAppearance();
  int? _selectedSubtitleTrackId;
  String? _caption;

  @override
  void initState() {
    super.initState();
    _start();
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _captionSub?.cancel();
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
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

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final settings = await loadPlaybackSettings(SharedPreferencesAsync());
      final forcedMethod = switch (resolveForcedPlayMethod(settings)) {
        'direct' => PlayMethod.direct,
        'transcode' => PlayMethod.transcode,
        _ => null,
      };
      var codecsVideo = List<String>.from(TvCapabilities.codecsVideo);
      if (settings.forceAv1 && !codecsVideo.contains('av1')) codecsVideo.add('av1');
      if (settings.disableAv1) codecsVideo.remove('av1');
      final started = await startPlayback(
        client,
        session,
        BuildPlaybackStartInput(
          fileId: widget.launch.fileId,
          profileId: session.profileId,
          startPosition: widget.launch.startPositionSeconds,
          forcedPlayMethod: forcedMethod,
          codecsVideo: codecsVideo,
        ),
      );
      final streamUrl = resolvePlaybackStreamUrl(session.serverUrl, started, session.accessToken);
      final backend = ref.read(videoBackendFactoryProvider)();
      await backend.load(streamUrl, startPosition: Duration(seconds: started.position.round()));
      await backend.play();
      if (!mounted) {
        await backend.dispose();
        return;
      }
      setState(() {
        _backend = backend;
        _playbackSession = started;
        _subtitleAppearance = settings.subtitleAppearance;
        _loading = false;
      });
      _positionSub = backend.positionStream.listen((position) {
        if (mounted) setState(() => _position = position);
      });
      _captionSub = backend.captionStream.listen((text) {
        if (mounted) setState(() => _caption = text);
      });
      _progressTimer = Timer.periodic(const Duration(milliseconds: _progressIntervalMs), (_) => _reportProgress());
      _autoSelectSubtitleTrack(backend, settings.preferredSubtitleLanguage);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiError ? e.message : 'Playback failed: $e';
          _loading = false;
        });
      }
    }
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
    final sessionId = _playbackSession?.sessionId;
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
    final backend = _backend;
    final sessionId = _playbackSession?.sessionId;
    if (sessionId != null) {
      await _reportProgress(paused: true);
      unawaited(stopPlaybackSession(ref.read(apiClientProvider), ref.read(sessionProvider)!, sessionId).catchError((_) {}));
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
              if (backend != null) Center(child: backend.buildSurface()),
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
                      Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _exit, child: const Text('Back')),
                    ],
                  ),
                ),
              if (_controlsVisible && backend != null)
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
                                  max: (backend.duration ?? const Duration(seconds: 1)).inMilliseconds.toDouble(),
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
                              const SizedBox(width: 16),
                              IconButton(iconSize: 32, color: PrairieColors.ink, onPressed: () => _seekBy(const Duration(seconds: -15)), icon: const Icon(Icons.replay_10)),
                              const SizedBox(width: 16),
                              IconButton(
                                iconSize: 48,
                                color: PrairieColors.amber,
                                onPressed: _togglePlayPause,
                                icon: Icon(backend.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                              ),
                              const SizedBox(width: 16),
                              IconButton(iconSize: 32, color: PrairieColors.ink, onPressed: () => _seekBy(const Duration(seconds: 15)), icon: const Icon(Icons.forward_10)),
                              if (backend.subtitleTracks.isNotEmpty) ...[
                                const SizedBox(width: 16),
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
