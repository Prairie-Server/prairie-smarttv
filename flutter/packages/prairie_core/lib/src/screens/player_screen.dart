import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:prairie_core/src/lib/detail_metadata.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _progressIntervalMs = 10000;
/// D-pad Left/Right on the seek bar — fixed seconds, not Material Slider's
/// default 5% of runtime (which is several minutes on a feature film).
@visibleForTesting
const playerSeekBarStep = Duration(seconds: 10);

/// Seek-bar step while Left/Right is held: the longer the hold, the bigger
/// the step, so crossing a feature film takes seconds rather than minutes.
@visibleForTesting
Duration playerSeekHoldStep(Duration heldFor) {
  if (heldFor < const Duration(seconds: 1)) return playerSeekBarStep;
  if (heldFor < const Duration(seconds: 3)) return const Duration(seconds: 30);
  if (heldFor < const Duration(seconds: 6)) return const Duration(minutes: 1);
  return const Duration(minutes: 2);
}

/// Left edge for a seek preview of [bubbleWidth] centered on the thumb at
/// [fraction] of a bar [barWidth] wide whose track is inset [trackInset] on
/// each side, clamped so the bubble stays within the bar.
@visibleForTesting
double seekPreviewLeft(double barWidth, double bubbleWidth, double fraction, double trackInset) {
  final thumbX = trackInset + (barWidth - trackInset * 2) * fraction.clamp(0.0, 1.0);
  return (thumbX - bubbleWidth / 2).clamp(0.0, math.max(0.0, barWidth - bubbleWidth)).toDouble();
}

/// How long the seek bar waits after the last Left/Right before seeking.
const _scrubCommitDelay = Duration(milliseconds: 400);
/// HLS remux/transcode sessions that stop advancing for this long after play
/// started are treated as a dead encode (ffmpeg exit) rather than forever-buffer.
const _hlsStallTimeout = Duration(seconds: 20);
/// AVPlay/webOS initialize must not hang forever if the HLS ladder never
/// becomes playable while the server encode clock keeps moving.
///
/// AVPlay's own `INITIAL_BUFFER_DURATION` (set on the HLS streaming property)
/// means initialize() doesn't resolve until several segments are on disk, and
/// a slow server/network delays every segment fetch behind that buffer fill —
/// remux is not exempt from this, so there's no per-play-method split here.
/// Matches [transcodeStartupTimeout] (the upstream HLS-readiness wait) so
/// this timeout isn't the tighter one in the chain.
const _initializeTimeout = Duration(seconds: 90);
/// How long remux seeking waits for input to pause before committing to an
/// actual session restart — see [_PlayerScreenState._seekToPosition].
const _seekDebounceDelay = Duration(milliseconds: 500);
/// Failure recoveries per plan chain before the error screen (the plan's
/// `attempt_count`; intent replans reset it). Lower than the protocol's 8
/// because each attempt on a TV can spend the full startup budget.
const _maxRecoveryAttempts = 3;
/// Transport-row skip buttons.
const _skipButtonStep = Duration(seconds: 10);
/// How long "Skip Intro" / "Watch Intro" stays up (web INTRO_PROMPT_SECONDS).
const _introPromptDuration = Duration(seconds: 5);
/// Up-next countdown before the next episode starts (web/Android).
const _upNextCountdownSeconds = 10;
/// A skip landing this close to the end is the end — finish the episode
/// instead of seeking to a frame the stream may never produce.
const _endSlackSeconds = 2.0;
/// Position frozen this long within [_endStallWindowSeconds] of the end
/// counts as the end — see [_PlayerScreenState._checkEndStall].
const _endStallTimeout = Duration(seconds: 3);
const _endStallWindowSeconds = 15.0;

/// Mirrors web's usePlaybackSession/VideoPlayer lifecycle on protocol v3:
/// start (with transient retry), sequenced progress, stop with the final
/// sample, timeline-driven seeking (`seek_reanchor` outside the seek window),
/// `failure_recovery` replans before any error screen, and route events.
///
/// Audio track switching is a `track_change` replan: TV players take a URL
/// only, so the server re-anchors the stream on the new track.
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
  StreamSubscription<void>? _completedSub;
  Duration _position = Duration.zero;
  /// Absolute-position anchor for the currently attached backend — see
  /// [PreparedPlayback.streamOriginSeconds]. Zero for direct/transcode
  /// (the backend's own position stream is already absolute); for remux,
  /// each reattach-at-a-new-position resets the native player's own clock
  /// to 0, so every raw position tick from here on needs this added back
  /// to read as an absolute position again.
  Duration _streamOrigin = Duration.zero;
  Duration _lastProgressPosition = Duration.zero;
  DateTime? _lastProgressAt;
  bool _loading = true;
  String? _error;
  bool _controlsVisible = true;
  bool _showStats = false;

  /// Path (no query, so no credentials) of the stream handed to the native
  /// player, for the stats overlay.
  String? _attachedStreamPath;
  Timer? _progressTimer;
  Timer? _endStallTimer;
  Timer? _hideControlsTimer;
  Timer? _stallTimer;
  /// Debounce for re-anchoring seeks — see [_seekToPosition].
  Timer? _seekDebounce;
  int _seekGeneration = 0;
  Duration? _pendingReanchorSeek;
  /// Live scrub/seek preview time shown above the seek bar (trickplay + clock).
  Duration? _seekPreviewTime;
  Timer? _seekPreviewHideTimer;
  /// Seek-bar scrub in progress: Left/Right move this target (and the
  /// preview) immediately, and one seek fires once input settles, instead of
  /// a native seek per key repeat.
  Duration? _scrubTarget;
  DateTime? _scrubHeldSince;
  Timer? _scrubCommitTimer;
  /// When the stream was attached; stall detection runs during prepare too.
  DateTime? _streamAttachedAt;
  bool _exiting = false;
  SubtitleAppearance _subtitleAppearance = const SubtitleAppearance();
  int? _selectedSubtitleTrackId;
  SubtitleCaption? _caption;
  CancelToken? _prepareCancel;
  bool _busyAudio = false;
  bool _busyQuality = false;

  /// A `failure_recovery` replan is in flight; see [_onPlaybackFailure].
  bool _recovering = false;

  /// Session returned by `/playback/start`; its play method labels the
  /// quality menu's Original entry.
  PlaybackSessionResponse? _basePlaybackSession;

  /// Active quality menu selection, keyed by id (`auto` / `original` / rung id).
  String _activeQualityId = 'original';
  List<QualityLadderRung> _qualityLadder = fallbackQualityLadder;
  String? _qualityError;

  /// Receives D-pad keys while chrome is hidden so nav can bring it back.
  final FocusNode _idleFocus = FocusNode(debugLabel: 'player.idle');
  final FocusNode _backFocus = FocusNode(debugLabel: 'player.back');
  final FocusNode _seekFocus = FocusNode(debugLabel: 'player.seek');
  final FocusNode _playFocus = FocusNode(debugLabel: 'player.play');
  /// The primary button of whichever overlay is up (skip pill / up next), so
  /// OK acts on it while the chrome is hidden.
  final FocusNode _overlayFocus = FocusNode(debugLabel: 'player.overlay');

  /// Server-side skip/autoplay preferences; null until loaded, during which
  /// nothing is skipped automatically.
  PlaybackSkipSettings? _skip;
  /// Marker regions of the playing file, source time.
  List<MarkerRegion> _markers = const [];
  /// Episodes around this one; null for movies or until loaded.
  SeriesContext? _series;
  /// Markers already acted on (skipped, prompted and answered) this session.
  final Set<String> _resolvedMarkers = {};
  /// Intro the "Skip Intro" / "Watch Intro" pill is for, if one is up.
  MarkerRegion? _introPrompt;
  bool _introPromptIsUndo = false;
  /// Intro already offered in "ask" mode while the playhead stays inside it,
  /// so the pill doesn't come back after timing out; cleared on leaving it.
  String? _introOfferedKey;
  Timer? _introPromptTimer;
  bool _upNextVisible = false;
  /// Viewer cancelled up next; stays cancelled for this episode.
  bool _upNextDismissed = false;
  int? _upNextSecondsLeft;
  Timer? _upNextTimer;
  /// Playback reached the end of the stream (or the credits were skipped
  /// to it); the player is now leaving or counting down to the next episode.
  bool _ended = false;
  /// The viewer (or the sleep timer) paused; a frozen position is not the end.
  bool _viewerPaused = false;
  bool _switchingEpisode = false;
  /// Wall-clock time the sleep timer pauses playback; null when off.
  DateTime? _sleepDeadline;
  Timer? _sleepTicker;

  String? get _contentId => widget.launch.contentId ?? widget.launch.watch?.contentId;
  EpisodeRef? get _previousEpisode => _contentId == null ? null : _series?.previousOf(_contentId!);
  EpisodeRef? get _nextEpisode => _contentId == null ? null : _series?.nextOf(_contentId!);

  /// The source runtime, from the plan. Deliberately not the native duration:
  /// that is the remaining runtime for remux and the produced-so-far edge of
  /// a growing HLS playlist, either of which would end playback early.
  double? get _sourceDurationSeconds {
    final seconds = _playbackSession?.durationSeconds;
    return seconds != null && seconds > 0 ? seconds : null;
  }

  @override
  void initState() {
    super.initState();
    _seekFocus.addListener(_onControlFocusChanged);
    _playFocus.addListener(_onControlFocusChanged);
    _backFocus.addListener(_onControlFocusChanged);
    final sleepDeadline = widget.launch.sleepDeadline;
    if (sleepDeadline != null && sleepTimerRemaining(sleepDeadline, DateTime.now()) != null) {
      _startSleepTicker(sleepDeadline);
    }
    _start();
    unawaited(_loadPlaybackExtras());
    _scheduleHideControls();
  }

  /// Skip preferences, the playing file's markers and the series
  /// neighborhood — none blocks playback, and each degrades to "feature off".
  Future<void> _loadPlaybackExtras() async {
    final client = ref.read(apiClientProvider);
    final session = ref.read(sessionProvider);
    if (session == null) return;
    unawaited(
      fetchPlaybackSkipSettings(client, session)
          .catchError((Object e) {
            debugPrint('prairie.player_screen: skip settings unavailable, using defaults: $e');
            return const PlaybackSkipSettings();
          })
          .then((skip) {
            if (mounted) setState(() => _skip = skip);
          }),
    );
    final contentId = _contentId;
    if (contentId == null) return;
    // Re-read with file_id: the server fills markers in for one version
    // only, and the launch's copy may have been read for a different one.
    WatchDetail? watch;
    try {
      watch = await fetchWatchDetail(client, session, contentId, fileId: widget.launch.fileId);
    } catch (e) {
      debugPrint('prairie.player_screen: watch detail for markers failed: $e');
      watch = widget.launch.watch;
    }
    if (!mounted || watch == null) return;
    final markers = selectFileVersion(watch, widget.launch.fileId)?.markers ?? const <MarkerRegion>[];
    setState(() => _markers = markers);
    final seriesId = watch.seriesId;
    final season = watch.seasonNumber;
    if (seriesId == null || seriesId.isEmpty || season == null) return;
    try {
      final series = await loadSeriesContext(
        client,
        ref.read(sessionProvider) ?? session,
        seriesId: seriesId,
        seriesTitle: watch.seriesTitle,
        currentSeason: season,
      );
      if (mounted) setState(() => _series = series);
    } catch (e) {
      debugPrint('prairie.player_screen: series episodes unavailable: $e');
    }
  }

  @override
  void dispose() {
    _prepareCancel?.cancel();
    _positionSub?.cancel();
    _captionSub?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _progressTimer?.cancel();
    _endStallTimer?.cancel();
    _hideControlsTimer?.cancel();
    _stallTimer?.cancel();
    _seekDebounce?.cancel();
    _seekPreviewHideTimer?.cancel();
    _scrubCommitTimer?.cancel();
    _introPromptTimer?.cancel();
    _upNextTimer?.cancel();
    _sleepTicker?.cancel();
    _seekFocus.removeListener(_onControlFocusChanged);
    _playFocus.removeListener(_onControlFocusChanged);
    _backFocus.removeListener(_onControlFocusChanged);
    _idleFocus.dispose();
    _backFocus.dispose();
    _seekFocus.dispose();
    _playFocus.dispose();
    _overlayFocus.dispose();
    // Widget teardown that bypasses [_exit] (route replace, error boundary)
    // must still stop the Prairie session and free the hardware decoder.
    final sessionId = _activeSessionId;
    _activeSessionId = null;
    if (sessionId != null && !_exiting) {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider);
      if (session != null) {
        unawaited(
          stopPlaybackSession(client, session, sessionId, position: _position.inMilliseconds / 1000.0)
              .catchError((_) {}),
        );
      }
    }
    final backend = _backend;
    _backend = null;
    if (backend != null) {
      unawaited(backend.dispose());
    }
    super.dispose();
  }

  void _onControlFocusChanged() {
    if (_seekFocus.hasFocus || _playFocus.hasFocus || _backFocus.hasFocus) {
      _scheduleHideControls();
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), _hideControlsNow);
  }

  void _hideControlsNow() {
    if (!mounted) return;
    _hideControlsTimer?.cancel();
    _seekPreviewHideTimer?.cancel();
    setState(() {
      _controlsVisible = false;
      _seekPreviewTime = null;
    });
    // Controls leave the tree with their FocusNodes — park focus on the
    // idle catcher (or an overlay button, so OK acts on it) so the next
    // D-pad event has somewhere to land.
    _focusIdleOrOverlay();
  }

  bool get _overlayVisible => _introPrompt != null || _upNextVisible || _manualSkipRegion != null;

  void _focusIdleOrOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controlsVisible) return;
      if (_overlayVisible && _overlayFocus.context != null) {
        _overlayFocus.requestFocus();
      } else {
        _idleFocus.requestFocus();
      }
    });
  }

  void _showSeekPreview(Duration time) {
    _seekPreviewHideTimer?.cancel();
    _seekPreviewTime = time;
    _seekPreviewHideTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _seekPreviewTime = null);
    });
  }

  TrickplayInfo? get _activeTrickplay {
    final watch = widget.launch.watch;
    if (watch == null) return null;
    final fileId = _playbackSession?.mediaFileId ?? widget.launch.fileId;
    return selectFileVersion(watch, fileId)?.trickplay ??
        (watch.versions.isNotEmpty ? watch.versions.first.trickplay : null);
  }

  void _showControls({bool focusPlay = false}) {
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
    if (!focusPlay) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controlsVisible) _playFocus.requestFocus();
    });
  }

  /// Any remote key while chrome is hidden re-shows it. Back/Escape still
  /// bubble to [PopScope] so they exit the player.
  KeyEventResult _onIdleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (isSystemRemoteKey(event.logicalKey)) return KeyEventResult.ignored;
    // Remote transport keys act directly, whatever has focus; focused
    // controls don't claim them, so they bubble up to here.
    final media = remoteMediaActionFor(event.logicalKey);
    if (media != null) return _onMediaKey(media, repeat: event is KeyRepeatEvent);
    if (_controlsVisible) {
      _scheduleHideControls();
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      return KeyEventResult.ignored;
    }
    // The skip pill / up-next card sit inside this Focus, so their keys
    // bubble here before the app's activate shortcut: OK and Left/Right must
    // reach the focused button, only Up/Down bring the chrome back.
    final onOverlay = FocusManager.instance.primaryFocus != _idleFocus;
    if (onOverlay &&
        event.logicalKey != LogicalKeyboardKey.arrowUp &&
        event.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    _showControls(focusPlay: true);
    return KeyEventResult.handled;
  }

  KeyEventResult _onMediaKey(RemoteMediaAction action, {required bool repeat}) {
    if (action == RemoteMediaAction.stop) {
      if (!repeat) unawaited(_exit());
      return KeyEventResult.handled;
    }
    // Show what the key did; focusing Play keeps the D-pad useful afterwards.
    if (!_controlsVisible) {
      _showControls(focusPlay: true);
    } else {
      _scheduleHideControls();
    }
    final playing = _backend?.isPlaying ?? false;
    switch (action) {
      case RemoteMediaAction.playPause:
        if (!repeat) unawaited(_togglePlayPause());
      case RemoteMediaAction.play:
        if (!repeat && !playing) unawaited(_togglePlayPause());
      case RemoteMediaAction.pause:
        if (!repeat && playing) unawaited(_togglePlayPause());
      case RemoteMediaAction.fastForward:
        unawaited(_seekBy(const Duration(seconds: 15)));
      case RemoteMediaAction.rewind:
        unawaited(_seekBy(const Duration(seconds: -15)));
      case RemoteMediaAction.stop:
        break;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onSeekKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final horizontal = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight;
    if (event is KeyUpEvent) {
      if (!horizontal) return KeyEventResult.ignored;
      // Releasing ends the hold, so the next press starts at the small step.
      _scrubHeldSince = null;
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    _scheduleHideControls();
    if (horizontal) {
      _scrub(key == LogicalKeyboardKey.arrowRight ? 1 : -1, repeat: event is KeyRepeatEvent);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      // The skip pill / up-next card floats just above the seek bar.
      (_overlayVisible && _overlayFocus.context != null ? _overlayFocus : _backFocus).requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrub(int direction, {required bool repeat}) {
    final now = DateTime.now();
    final heldSince = repeat ? (_scrubHeldSince ??= now) : (_scrubHeldSince = now);
    final step = playerSeekHoldStep(now.difference(heldSince));
    var next = (_scrubTarget ?? _position) + step * direction;
    final duration = _totalDuration;
    if (next < Duration.zero) next = Duration.zero;
    if (duration != null && duration > Duration.zero && next > duration) next = duration;
    _showSeekPreview(next);
    setState(() => _scrubTarget = next);
    _scrubCommitTimer?.cancel();
    _scrubCommitTimer = Timer(_scrubCommitDelay, _commitScrub);
  }

  void _commitScrub() {
    _scrubCommitTimer?.cancel();
    final target = _scrubTarget;
    _scrubTarget = null;
    _scrubHeldSince = null;
    if (target == null || !mounted) return;
    unawaited(_seekToPosition(target));
  }

  String? _sourceResolutionForFile(WatchDetail? detail, int fileId) {
    if (detail == null) return null;
    for (final version in detail.versions) {
      if (version.fileId == fileId) return version.resolution;
    }
    return detail.versions.isNotEmpty ? detail.versions.first.resolution : null;
  }

  int _sourceHeightForFile(WatchDetail? detail, int fileId) {
    final version = detail == null ? null : selectFileVersion(detail, fileId);
    final probed = version?.videoTracks.isNotEmpty == true ? version!.videoTracks.first.height : null;
    return sourceHeightForFile(
      ladder: _qualityLadder,
      resolution: version?.resolution ?? _sourceResolutionForFile(detail, fileId),
      probedHeight: probed,
    );
  }

  List<QualityOption> get _qualityOptions {
    // Every option but `original` requires an actual re-encode, which goes
    // out over HLS — unsupported on this backend (see
    // TvPlaybackCapabilities.supportsHlsTranscode). `original` alone is a
    // no-op (you're already playing it), so there's nothing meaningful left
    // to offer; hide the menu entirely rather than show a picker with one
    // inert entry.
    if (!ref.read(tvCapabilitiesProvider).supportsHlsTranscode) return const [];
    final fileId = _playbackSession?.mediaFileId ?? widget.launch.fileId;
    final nativeHeight = _sourceHeightForFile(widget.launch.watch, fileId);
    return buildQualityOptions(
      ladder: qualityLadderForSourceHeight(_qualityLadder, nativeHeight),
      nativeHeight: nativeHeight,
      playMethod: _basePlaybackSession?.playMethod ?? _playbackSession?.playMethod,
      sourceResolutionLabel: _sourceResolutionForFile(widget.launch.watch, fileId),
    );
  }

  /// Clears the `_busyAudio`/`_loading` lock set at the top of [_chooseAudio],
  /// but only when [cancel] is still the current in-flight prepare — if a
  /// newer `_chooseAudio`/`_start` call already superseded it (via
  /// `_prepareCancel?.cancel()`), that newer call owns those flags now and
  /// clearing them here would let a third call slip past the `_busyAudio`
  /// guard while the newer one is still running.
  void _clearAudioBusyIfCurrent([CancelToken? cancel]) {
    if (!mounted || (cancel != null && !identical(_prepareCancel, cancel))) return;
    setState(() {
      _busyAudio = false;
      _loading = false;
    });
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
    if (current == null || index == current.audioTrackIndex) return;
    await _restartSessionAt(audioTrackIndex: index, positionSeconds: _position.inMilliseconds / 1000.0);
  }

  Future<void> _pickQuality() async {
    final options = _qualityOptions;
    if (options.isEmpty) return;
    final activeId = _activeQualityId;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrairieColors.bgElevated,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (_qualityError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(_qualityError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ),
            for (final opt in options)
              ListTile(
                title: Text(opt.label, style: const TextStyle(color: PrairieColors.ink)),
                subtitle: opt.sublabel.isEmpty
                    ? null
                    : Text(opt.sublabel, style: const TextStyle(color: PrairieColors.muted, fontSize: 12)),
                trailing: opt.id == activeId ? const Icon(Icons.check, color: PrairieColors.amber) : null,
                onTap: () => Navigator.of(context).pop<String>(opt.id),
              ),
          ],
        ),
      ),
    );
    if (choice == null || choice == activeId) return;
    await _switchQuality(choice);
  }

  /// Switches quality with a protocol-v3 `quality_change` replan; the menu id
  /// (`auto` / `original` / rung id) is the `quality_preference`.
  Future<void> _switchQuality(String qualityId) async {
    final current = _playbackSession;
    if (current == null || _busyQuality || _busyAudio || _exiting || _recovering) return;
    if (qualityId == _activeQualityId) return;

    setState(() {
      _busyQuality = true;
      _qualityError = null;
      _activeQualityId = qualityId;
      _loading = true;
    });

    final cancel = CancelToken();
    _prepareCancel?.cancel();
    _prepareCancel = cancel;
    final position = _position.inMilliseconds / 1000.0;
    final backendBefore = _backend;

    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final settings = await loadPlaybackSettings(SharedPreferencesAsync());
      final deviceCaps = _deviceCaps(settings);

      final replanned = await replanPlaybackQuality(
        client,
        session,
        current,
        qualityPreference: qualityId,
        positionSeconds: position,
      );
      final prepared = await prepareProtocolV3Decision(
        client,
        // Fresh: a preceding call may have refreshed the access token.
        ref.read(sessionProvider) ?? session,
        replanned,
        position,
        cancelToken: cancel,
      );
      if (!mounted || _exiting || cancel.isCancelled) {
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _clearQualityBusyIfCurrent(cancel);
        return;
      }
      await _attachPrepared(
        prepared: prepared,
        client: client,
        session: session,
        cancel: cancel,
        settings: settings,
        deviceCaps: deviceCaps,
        clearBusy: _clearQualityBusyIfCurrent,
      );
    } catch (e, stack) {
      debugPrint('prairie.player_screen: _switchQuality failed: $e\n$stack');
      if (mounted && !_exiting) {
        setState(() {
          _qualityError = e is ApiError ? e.message : 'Could not switch quality';
          _busyQuality = false;
          _loading = false;
        });
        // Past the point the old stream was torn down: recover instead of
        // leaving a dead surface.
        if (!identical(_backend, backendBefore) || _backend == null) unawaited(_onPlaybackFailure(e));
      }
    }
  }

  void _clearQualityBusyIfCurrent([CancelToken? cancel]) {
    if (!mounted) return;
    if (cancel != null && !identical(_prepareCancel, cancel)) return;
    setState(() {
      _busyQuality = false;
      _loading = false;
    });
  }

  /// Attaches [prepared] as the playing stream: disposes the previous
  /// backend, mounts the new surface, initializes at the plan's player start,
  /// plays, and wires position / caption / error streams. Shared by start,
  /// quality/track changes, seek re-anchors and failure recovery so they all
  /// honour the plan timeline the same way.
  Future<void> _attachPrepared({
    required PreparedPlayback prepared,
    required ApiClient client,
    required PrairieSession session,
    required CancelToken cancel,
    required PlaybackSettings settings,
    required TvPlaybackCapabilities deviceCaps,
    required void Function([CancelToken?]) clearBusy,
    String? subtitleLanguage,
  }) async {
    _activeSessionId = prepared.session.sessionId;
    await _positionSub?.cancel();
    await _captionSub?.cancel();
    await _errorSub?.cancel();
    await _completedSub?.cancel();
    _stallTimer?.cancel();
    final oldBackend = _backend;
    _backend = null;
    await oldBackend?.dispose();

    final backend = ref.read(videoBackendFactoryProvider)(enableDiagnostics: settings.enableDiagnosticsBeacon);
    _attachedStreamPath = Uri.tryParse(prepared.streamUrl)?.path;
    backend.attach(
      prepared.streamUrl,
      maxResolution: deviceCaps.maxResolution,
      contentAspectRatio: contentAspectRatioForFile(widget.launch.watch, prepared.session.mediaFileId),
    );
    // Mount the hole-punch surface BEFORE initialize — PlusPlayer prepares
    // against the display rect; awaiting init with no VideoPlayer in the
    // tree leaves Direct Play streaming on the server while Flutter spins.
    final origin = Duration(milliseconds: (prepared.streamOriginSeconds * 1000).round());
    setState(() {
      _backend = backend;
      _playbackSession = prepared.session;
      _streamOrigin = origin;
      _position = origin + Duration(milliseconds: (prepared.playerStartSeconds * 1000).round());
      _selectedSubtitleTrackId = null;
      _caption = null;
    });
    _streamAttachedAt = DateTime.now();
    unawaited(reportPlaybackRouteEvent(client, session, prepared.session, 'plan_selected'));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _exiting || cancel.isCancelled) {
      await backend.dispose();
      await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
      clearBusy(cancel);
      return;
    }

    // Initialize has its own [_initializeTimeout] budget (matched to the
    // upstream HLS-readiness wait) — the stall timer below must not start
    // until playback has actually begun, or it preempts that budget with a
    // much tighter one.
    final startAt = prepared.playerStartSeconds > 0
        ? Duration(milliseconds: (prepared.playerStartSeconds * 1000).round())
        : null;
    await _initializeBackend(
      backend,
      startPosition: startAt,
      playMethod: prepared.session.playMethod,
      playbackSession: prepared.session,
    );
    await backend.play();
    _viewerPaused = false;
    if (!mounted || _exiting || cancel.isCancelled) {
      await backend.dispose();
      await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
      clearBusy(cancel);
      return;
    }

    clearBusy(cancel);
    _lastProgressPosition = _position;
    _lastProgressAt = DateTime.now();
    if (needsHlsBootstrap(prepared.session.playMethod)) {
      _stallTimer?.cancel();
      _stallTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkHlsStall());
    }
    _positionSub = backend.positionStream.listen((pos) {
      if (!mounted) return;
      final absolute = _streamOrigin + pos;
      if (absolute != _lastProgressPosition) {
        _lastProgressPosition = absolute;
        _lastProgressAt = DateTime.now();
      }
      setState(() => _position = absolute);
      _onPlaybackTick();
    });
    _completedSub = backend.completedStream.listen((_) {
      if (!mounted || !identical(_backend, backend)) return;
      _onPlaybackEnded();
    });
    _captionSub = backend.captionStream.listen((caption) {
      if (mounted) setState(() => _caption = caption);
    });
    _errorSub = backend.errorStream.listen((message) {
      if (!mounted || _exiting || _error != null || !identical(_backend, backend)) return;
      unawaited(_onPlaybackFailure(message));
    });
    _progressTimer ??= Timer.periodic(const Duration(milliseconds: _progressIntervalMs), (_) => _reportProgress());
    _endStallTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _checkEndStall());
    unawaited(reportPlaybackRouteEvent(client, session, prepared.session, 'first_frame'));
    if (startAt != null) unawaited(_verifyStartPosition(backend, prepared.session, startAt));
    unawaited(_autoSelectSubtitleTrack(backend, subtitleLanguage ?? settings.preferredSubtitleLanguage));
    _showControls();
  }

  /// Direct play resumes by seeking the native player to the plan's
  /// `player_start_seconds` right after initialize. Some Tizen sources
  /// silently drop that seek (or an original-file audio-track selection
  /// resets it), so playback would start at 0 with a resume point on screen.
  /// Check the first real position tick and re-seek once if it missed.
  Future<void> _verifyStartPosition(VideoBackend backend, PlaybackSessionResponse plan, Duration target) async {
    if (plan.playMethod != 'direct') return;
    Duration first;
    try {
      first = await backend.positionStream.first.timeout(const Duration(seconds: 5));
    } catch (_) {
      return;
    }
    if (!mounted || _exiting || !identical(_backend, backend)) return;
    if ((first - target).abs() < const Duration(seconds: 5)) return;
    backend.reportDiagnostic('start:resume-missed:at=${first.inSeconds}:want=${target.inSeconds}');
    try {
      await backend.seekTo(target);
    } on PlatformException catch (err) {
      backend.reportDiagnostic('start:reseek-failed:${err.message ?? err.code}');
    }
  }

  void _clearLoadingIfCurrent([CancelToken? cancel]) {
    if (!mounted) return;
    if (cancel != null && !identical(_prepareCancel, cancel)) return;
    setState(() => _loading = false);
  }

  /// Fatal, user-facing error: recovery is exhausted or not possible.
  void _showFatal(String message) {
    if (!mounted || _exiting) return;
    _stallTimer?.cancel();
    setState(() {
      _error = message;
      _loading = false;
      _busyAudio = false;
      _busyQuality = false;
    });
  }

  String _describeFailure(Object e) {
    if (e is String) return e;
    if (e is ApiError) return e.message;
    if (e is HlsProbeAuthError) return 'Not authorized to play this stream. Try signing in again.';
    if (e is TranscodeStartupTimeoutError) return e.message;
    if (e is PlaybackTerminalError) return e.message;
    if (e is PlaybackRecoveryExhaustedError) return e.toString();
    if (e is PlatformException) return 'Playback failed: ${e.message ?? e.code}';
    return 'Playback failed: $e';
  }

  /// Mirrors web's `recoverFromFailure`: the device could not play the plan
  /// (native player error, fatal decode, startup/transport stall), so ask the
  /// server for another route with a `failure_recovery` replan — the failed
  /// plan's key joins `attempted_plan_keys` and the server excludes it — and
  /// play that before giving up. Bounded by [_maxRecoveryAttempts] (the
  /// plan's `attempt_count`, which intent replans reset). Only when no
  /// recovery is possible does the error screen appear.
  Future<void> _onPlaybackFailure(Object cause, {String? classification}) async {
    if (!mounted || _exiting || _recovering || _error != null) return;
    var failureClass = classification ?? classifyPlaybackFailure(cause);
    var failureMessage = _describeFailure(cause);
    final initial = _playbackSession;
    if (initial == null || initial.planId == null) {
      _showFatal(failureMessage);
      return;
    }
    _recovering = true;
    _stallTimer?.cancel();
    _seekDebounce?.cancel();
    final cancel = CancelToken();
    _prepareCancel?.cancel();
    _prepareCancel = cancel;
    setState(() => _loading = true);
    // Counted separately from the plan's attempt_count: a replan request that
    // itself fails (5xx, network) leaves the plan unchanged, so attempt_count
    // alone would never end the loop.
    var iterations = 0;
    try {
      while (mounted && !_exiting && !cancel.isCancelled) {
        final plan = _playbackSession ?? initial;
        if (plan.attemptCount > _maxRecoveryAttempts || iterations >= _maxRecoveryAttempts) break;
        if (iterations > 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!mounted || _exiting || cancel.isCancelled) break;
        }
        iterations++;
        final client = ref.read(apiClientProvider);
        final session = ref.read(sessionProvider);
        if (session == null) break;
        final position = _position.inMilliseconds / 1000.0;
        _backend?.reportDiagnostic('recover:$failureClass:attempt=${plan.attemptCount}');
        unawaited(reportPlaybackRouteEvent(
          client,
          session,
          plan,
          'plan_failed',
          failureClassification: failureClass,
          diagnostics: {'error_cause': failureMessage},
        ));
        try {
          final replanned = await replanPlaybackFailure(
            client,
            session,
            plan,
            classification: failureClass,
            message: failureMessage,
            positionSeconds: position,
          );
          // Exit already stopped the session it knew about; this one would
          // otherwise keep a transcode (or tuner) running.
          if (!mounted || _exiting || cancel.isCancelled) {
            unawaited(stopPlaybackSession(client, session, replanned.sessionId).catchError((_) {}));
            return;
          }
          // Adopt the plan identity now so a failure preparing it counts
          // toward the next attempt and exit stops the right session.
          _playbackSession = replanned;
          _activeSessionId = replanned.sessionId;
          final settings = await loadPlaybackSettings(SharedPreferencesAsync());
          final deviceCaps = _deviceCaps(settings);
          final prepared = await prepareProtocolV3Decision(
            client,
            ref.read(sessionProvider) ?? session,
            replanned,
            position,
            cancelToken: cancel,
          );
          if (!mounted || _exiting || cancel.isCancelled) {
            // A repeat stop of a session exit already stopped is harmless.
            unawaited(stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {}));
            return;
          }
          await _attachPrepared(
            prepared: prepared,
            client: client,
            session: session,
            cancel: cancel,
            settings: settings,
            deviceCaps: deviceCaps,
            clearBusy: _clearLoadingIfCurrent,
          );
          return;
        } on PlaybackRecoveryExhaustedError {
          break;
        } catch (e, stack) {
          debugPrint('prairie.player_screen: failure recovery attempt failed: $e\n$stack');
          failureMessage = _describeFailure(e);
          // A refused replan (4xx / terminal outcome) means the server has no
          // other route; retrying the same request cannot change that.
          if (e is PlaybackTerminalError || (e is ApiError && e.status >= 400 && e.status < 500)) break;
          failureClass = classifyPlaybackFailure(e);
        }
      }
    } finally {
      _recovering = false;
    }
    if (!cancel.isCancelled) _showFatal(failureMessage);
  }

  TvPlaybackCapabilities _deviceCaps(PlaybackSettings settings) => applyAudioChannelOverride(
    applyAv1AdvertiseOverrides(
      ref.read(tvCapabilitiesProvider),
      forceAv1: settings.forceAv1,
      disableAv1: settings.disableAv1,
    ),
    is8KPanel: settings.is8KPanel,
  );

  /// Restarts the active playback session at [audioTrackIndex] /
  /// [positionSeconds] via a protocol-v3 replan (`track_change`, or
  /// `seek_reanchor` when the track is unchanged) + a fresh
  /// [prepareProtocolV3Decision]. Used both for explicit audio-track switches
  /// and, in [_seekToPosition], for seeks the current transport cannot
  /// serve (outside the plan's seek window, or any progressive-remux seek).
  Future<void> _restartSessionAt({required int audioTrackIndex, required double positionSeconds}) async {
    final current = _playbackSession;
    final sessionId = _activeSessionId ?? current?.sessionId;
    if (current == null || sessionId == null || _busyAudio || _busyQuality || _exiting || _recovering) return;

    setState(() {
      _busyAudio = true;
      _error = null;
      _loading = true;
    });

    final cancel = CancelToken();
    _prepareCancel?.cancel();
    _prepareCancel = cancel;
    final backendBefore = _backend;

    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final settings = await loadPlaybackSettings(SharedPreferencesAsync());
      final deviceCaps = _deviceCaps(settings);

      final position = positionSeconds < 0 ? 0.0 : positionSeconds;
      final isSeek = audioTrackIndex == current.audioTrackIndex;
      if (isSeek) unawaited(reportPlaybackRouteEvent(client, session, current, 'seek_reanchor_requested'));
      final nextSession = isSeek
          ? await replanPlaybackSeek(client, session, current, positionSeconds: position)
          : await replanPlaybackAudio(
              client,
              session,
              current,
              audioTrackIndex: audioTrackIndex,
              positionSeconds: position,
            );
      if (!mounted || _exiting || cancel.isCancelled) {
        _clearAudioBusyIfCurrent(cancel);
        return;
      }

      final prepared = await prepareProtocolV3Decision(
        client,
        // Fresh: a preceding call may have refreshed the access token.
        ref.read(sessionProvider) ?? session,
        nextSession,
        position,
        cancelToken: cancel,
      );
      if (!mounted || _exiting || cancel.isCancelled) {
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _clearAudioBusyIfCurrent(cancel);
        return;
      }

      await _attachPrepared(
        prepared: prepared,
        client: client,
        session: session,
        cancel: cancel,
        settings: settings,
        deviceCaps: deviceCaps,
        clearBusy: _clearAudioBusyIfCurrent,
      );
      if (isSeek) unawaited(reportPlaybackRouteEvent(client, session, prepared.session, 'seek_reanchored'));
    } catch (e, stack) {
      debugPrint('prairie.player_screen: _restartSessionAt failed: $e\n$stack');
      if (!mounted || _exiting) return;
      setState(() => _busyAudio = false);
      if (!identical(_backend, backendBefore) || _backend == null) {
        // The old stream is already gone; recover rather than strand the
        // viewer on a dead surface.
        unawaited(_onPlaybackFailure(e));
        return;
      }
      // The replan was refused before anything was torn down: the previous
      // stream keeps playing, like web leaves the plan on screen.
      setState(() => _loading = false);
      _notify(_describeFailure(e));
    }
  }

  /// Non-fatal notice over a stream that keeps playing.
  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
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

    PlaybackSessionResponse? started;
    try {
      final client = ref.read(apiClientProvider);
      final identity = ref.read(clientIdentityProvider);
      final session = ref.read(sessionProvider)!;
      final settings = await loadPlaybackSettings(SharedPreferencesAsync());
      final deviceCaps = _deviceCaps(settings);
      final forcedMethod = switch (resolveForcedPlayMethod(settings)) {
        'direct' => PlayMethod.direct,
        'transcode' => PlayMethod.transcode,
        _ => null,
      };

      // An explicit pick wins; otherwise avoid a default the device cannot
      // decode (e.g. TrueHD beside an AC-3 companion), which would force a
      // server audio re-encode instead of playing the original file.
      final launchVersion = widget.launch.watch == null ? null : selectFileVersion(widget.launch.watch!, widget.launch.fileId);
      final initialAudioTrackIndex = widget.launch.initialAudioTrackIndex ??
          selectPlayableAudioTrack(
            launchVersion?.audioTracks ?? const <AudioTrackInfo>[],
            deviceCaps.codecsAudio,
            deviceCaps.maxAudioChannels,
          );
      final startedSession = await startPlayback(
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
          maxAudioChannels: deviceCaps.maxAudioChannels,
          audioTrackIndex: initialAudioTrackIndex,
          devicePlatform: identity.devicePlatform,
          appVersion: identity.appVersion,
          appBuild: identity.appBuild,
          appChannel: identity.appChannel,
        ),
        cancelToken: cancel,
      );
      started = startedSession;
      _activeSessionId = startedSession.sessionId;
      _basePlaybackSession = startedSession;
      prefetchQualityLadder(client, session);
      unawaited(
        fetchQualityLadder(client, session).then((ladder) {
          if (!mounted) return;
          setState(() => _qualityLadder = ladder.isEmpty ? fallbackQualityLadder : ladder);
        }),
      );

      if (!mounted || _exiting || cancel.isCancelled) {
        await stopPlaybackSession(client, session, startedSession.sessionId).catchError((_) {});
        _activeSessionId = null;
        return;
      }

      // Positions come from the plan timeline; the requested position is only
      // the fallback for a plan without one. A plan that cannot be prepared
      // (HLS never ready, auth) is a plan failure: the session is kept so
      // failure recovery can replan it.
      final seekAt = widget.launch.startPositionSeconds ?? startedSession.position;
      final prepared = await prepareProtocolV3Decision(
        client,
        // Fresh: a preceding call may have refreshed the access token.
        ref.read(sessionProvider) ?? session,
        startedSession,
        seekAt,
        cancelToken: cancel,
      );

      if (!mounted || _exiting || cancel.isCancelled) {
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _activeSessionId = null;
        return;
      }

      setState(() => _subtitleAppearance = settings.subtitleAppearance);
      await _attachPrepared(
        prepared: prepared,
        client: client,
        session: session,
        cancel: cancel,
        settings: settings,
        deviceCaps: deviceCaps,
        clearBusy: _clearLoadingIfCurrent,
        subtitleLanguage: widget.launch.initialSubtitleLanguage,
      );
      if (!mounted || _exiting || cancel.isCancelled) return;
      final initialAudio = widget.launch.initialAudioTrackIndex;
      if (initialAudio != null && initialAudio != (_playbackSession?.audioTrackIndex ?? 0)) {
        unawaited(_chooseAudio(initialAudio));
      }
    } catch (e, stack) {
      debugPrint('prairie.player_screen: _start failed: $e\n$stack');
      if (!mounted || _exiting || cancel.isCancelled) return;
      final plan = _playbackSession ?? started;
      if (plan != null) {
        // The start produced a plan the device could not play: recover
        // through the server before showing an error.
        _playbackSession ??= plan;
        unawaited(_onPlaybackFailure(e));
        return;
      }
      _showFatal(_describeFailure(e));
    }
  }

  void _checkHlsStall() {
    if (!mounted || _exiting || _error != null || _recovering) return;
    final backend = _backend;
    if (backend == null) return;
    // The timer only ever starts after a successful `play()` (see
    // [_attachPrepared]), so this is purely a post-start "stopped producing
    // media" detector — not a substitute for [_initializeTimeout]. A user
    // pause freezes `_lastProgressAt` (it only advances on a position-stream
    // tick), so a paused stream must not be judged stalled just for sitting
    // still — resuming refreshes `_lastProgressAt` in [_togglePlayPause].
    if (!backend.isPlaying) return;
    final lastAt = _lastProgressAt ?? _streamAttachedAt;
    if (lastAt == null) return;
    if (DateTime.now().difference(lastAt) < _hlsStallTimeout) return;
    _stallTimer?.cancel();
    unawaited(_onPlaybackFailure(
      'Playback stalled — the stream stopped producing media.',
      classification: 'transport_stall',
    ));
  }

  Future<void> _initializeBackend(
    VideoBackend backend, {
    Duration? startPosition,
    String? playMethod,
    PlaybackSessionResponse? playbackSession,
  }) async {
    final timeout = _initializeTimeout;
    final startedAt = DateTime.now();
    backend.reportDiagnostic('init:start:method=$playMethod:budget=${timeout.inSeconds}');
    try {
      await backend.initialize(startPosition: startPosition).timeout(timeout);
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        'prairie.player_screen: Player initialize succeeded in ${elapsedMs}ms (playMethod=$playMethod, budget=${timeout.inSeconds}s)',
      );
      backend.reportDiagnostic('init:done:${elapsedMs}ms');
    } on TimeoutException {
      debugPrint('prairie.player_screen: Player initialize timed out after ${timeout.inSeconds}s (playMethod=$playMethod)');
      backend.reportDiagnostic('init:TIMEOUT:${timeout.inSeconds}s');
      throw StateError('Player initialize timed out after ${timeout.inSeconds}s');
    }
    if (playbackSession != null) await _applyOriginalAudioSelection(backend, playbackSession);
  }

  /// Original-file playback serves every stream untouched, so a non-default
  /// audio track the server planned (we claim client_selected_audio_track_v1)
  /// must be selected in the native player. Remux/HLS already carry only the
  /// planned track.
  Future<void> _applyOriginalAudioSelection(VideoBackend backend, PlaybackSessionResponse session) async {
    if (session.playMethod != 'direct') return;
    final watch = widget.launch.watch;
    final version = watch == null ? null : selectFileVersion(watch, session.mediaFileId);
    final tracks = version?.audioTracks ?? const <AudioTrackInfo>[];
    var defaultIndex = tracks.indexWhere((t) => t.isDefault == true);
    if (defaultIndex < 0) defaultIndex = 0;
    if (session.audioTrackIndex == defaultIndex) return;
    try {
      final index = session.audioTrackIndex;
      await backend.selectAudioTrack(
        index,
        track: index >= 0 && index < tracks.length ? tracks[index] : null,
        sourceTrackCount: tracks.length,
      );
    } catch (err) {
      backend.reportDiagnostic('audio:select-failed:$err');
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
            for (final (i, track) in backend.subtitleTracks.indexed)
              ListTile(
                title: Text(
                  _nativeSubtitleLabel(track.language, i),
                  style: const TextStyle(color: PrairieColors.ink),
                ),
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

  /// Stops the session, frees the decoder, and routes to [to] — the next
  /// episode's player — or back where the player was opened from.
  Future<void> _exit({Route? to}) async {
    if (_exiting) return;
    _exiting = true;
    _prepareCancel?.cancel();
    final backend = _backend;
    _backend = null;
    final sessionId = _activeSessionId ?? _playbackSession?.sessionId;
    _activeSessionId = null;
    _playbackSession = null;
    _progressTimer?.cancel();
    _endStallTimer?.cancel();
    _stallTimer?.cancel();
    _seekDebounce?.cancel();
    _introPromptTimer?.cancel();
    _upNextTimer?.cancel();
    _sleepTicker?.cancel();
    await _errorSub?.cancel();
    _errorSub = null;
    await _completedSub?.cancel();
    _completedSub = null;
    if (sessionId != null) {
      // Await stop so Back cannot race a new play against a still-open session
      // on the single hardware decoder / server encode slot. The stop carries
      // the final position sample (v2), so the resume point is saved with it.
      final session = ref.read(sessionProvider);
      if (session != null) {
        await stopPlaybackSession(
          ref.read(apiClientProvider),
          session,
          sessionId,
          position: _position.inMilliseconds / 1000.0,
        ).catchError((_) {});
      }
    }
    await backend?.dispose();
    if (!mounted) return;
    ref.read(routeProvider.notifier).go(to ?? widget.back);
  }

  /// Runs on every position tick: end-of-stream fallback, intro/recap/
  /// credits handling and the up-next trigger, all against source time.
  void _onPlaybackTick() {
    if (_loading || _exiting || _ended || _switchingEpisode || _recovering || _error != null) return;
    if (_scrubTarget != null || _pendingReanchorSeek != null) return;
    final t = _position.inMilliseconds / 1000.0;
    final total = _sourceDurationSeconds;
    // Not every stream raises the native completion event (the plugins'
    // own handler pauses and seeks to the end, which can replay the last
    // second), so reaching the source runtime counts as the end too.
    if (total != null && t >= total - 1) {
      _onPlaybackEnded();
      return;
    }
    final skip = _skip;
    if (skip == null) return;

    final intro = activeMarker(_markers, MarkerKind.intro, t);
    if (intro == null || intro.key != _introOfferedKey) _introOfferedKey = null;
    final prompt = _introPrompt;
    if (prompt != null && !_introPromptIsUndo && intro != prompt) {
      _hideIntroPrompt(); // Seeked out of the intro.
    } else if (intro != null && prompt == null && !_resolvedMarkers.contains(intro.key) && _introOfferedKey != intro.key) {
      switch (skip.introSkipMode) {
        case IntroSkipMode.never:
          _resolvedMarkers.add(intro.key);
        case IntroSkipMode.ask:
          _introOfferedKey = intro.key;
          _showIntroPrompt(intro, undo: false);
        case IntroSkipMode.always:
          _resolvedMarkers.add(intro.key);
          _skipTo(intro.end);
          _showIntroPrompt(intro, undo: true);
          return;
      }
    }

    for (final (kind, auto) in [(MarkerKind.recap, skip.autoSkipRecap), (MarkerKind.credits, skip.autoSkipCredits)]) {
      final region = activeMarker(_markers, kind, t);
      if (!auto || region == null || _resolvedMarkers.contains(region.key)) continue;
      _resolvedMarkers.add(region.key);
      _skipTo(region.end);
      return;
    }

    _updateUpNext(t);
    // A manual-skip pill comes and goes with the playhead rather than an
    // event; move focus only when that changes, never off a button the
    // viewer navigated to.
    final overlay = _overlayVisible;
    if (overlay != _overlayWasVisible) {
      _overlayWasVisible = overlay;
      if (!_controlsVisible) _focusIdleOrOverlay();
    }
  }

  bool _overlayWasVisible = false;

  /// Seeks past a marker, or finishes the episode when that lands at its end.
  void _skipTo(double seconds) {
    final total = _sourceDurationSeconds;
    if (total != null && seconds >= total - _endSlackSeconds) {
      _onPlaybackEnded();
      return;
    }
    unawaited(_seekToPosition(Duration(milliseconds: (seconds * 1000).round()), revealChrome: false));
  }

  /// Recap/credits/preview the viewer can skip by hand: the active one that
  /// isn't skipped automatically, while no intro pill or up-next card is up.
  MarkerRegion? get _manualSkipRegion {
    if (_introPrompt != null || _upNextVisible || _ended || _loading || _error != null) return null;
    final t = _position.inMilliseconds / 1000.0;
    for (final kind in const [MarkerKind.recap, MarkerKind.credits, MarkerKind.preview]) {
      final region = activeMarker(_markers, kind, t);
      if (region != null && !_resolvedMarkers.contains(region.key)) return region;
    }
    return null;
  }

  void _showIntroPrompt(MarkerRegion intro, {required bool undo}) {
    _introPromptTimer?.cancel();
    setState(() {
      _introPrompt = intro;
      _introPromptIsUndo = undo;
    });
    // ponytail: wall-clock timeout; web freezes it while paused.
    _introPromptTimer = Timer(_introPromptDuration, _hideIntroPrompt);
    if (!_controlsVisible) _focusIdleOrOverlay();
  }

  void _hideIntroPrompt() {
    _introPromptTimer?.cancel();
    if (!mounted || _introPrompt == null) return;
    final hadFocus = _overlayFocus.hasFocus;
    setState(() => _introPrompt = null);
    if (hadFocus && !_controlsVisible) _focusIdleOrOverlay();
  }

  void _onIntroPromptPressed() {
    final intro = _introPrompt;
    if (intro == null) return;
    _resolvedMarkers.add(intro.key);
    final undo = _introPromptIsUndo;
    _hideIntroPrompt();
    _skipTo(undo ? intro.start : intro.end);
  }

  /// Shows up next on entering the trailing credits/preview run, when the
  /// series has a next episode — or, with no credits marked, one countdown
  /// before the end so it runs out as the episode does. Leaving the run (seek
  /// back) hides it again.
  void _updateUpNext(double t) {
    final next = _nextEpisode;
    final skip = _skip;
    final total = _sourceDurationSeconds;
    final start = next == null || skip == null || total == null
        ? null
        : autoplayRegionStart(_markers, total, allowPreview: skip.autoPlayNextPreview) ??
            total - _upNextCountdownSeconds;
    if (start == null || t < start) {
      if (_upNextVisible) _hideUpNext();
      return;
    }
    if (_upNextVisible || _upNextDismissed) return;
    _showUpNext(countdown: skip!.autoPlayNext);
  }

  void _showUpNext({required bool countdown}) {
    _upNextTimer?.cancel();
    setState(() {
      _upNextVisible = true;
      _upNextSecondsLeft = countdown ? _upNextCountdownSeconds : null;
    });
    if (countdown) {
      _upNextTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        // Holds while the viewer has paused (not once the stream has ended).
        if (!_ended && !(_backend?.isPlaying ?? false)) return;
        final left = (_upNextSecondsLeft ?? 1) - 1;
        if (left > 0) {
          setState(() => _upNextSecondsLeft = left);
          return;
        }
        _upNextTimer?.cancel();
        final next = _nextEpisode;
        if (next != null) unawaited(_playEpisode(next));
      });
    }
    if (!_controlsVisible) _focusIdleOrOverlay();
  }

  void _hideUpNext() {
    _upNextTimer?.cancel();
    final hadFocus = _overlayFocus.hasFocus;
    setState(() {
      _upNextVisible = false;
      _upNextSecondsLeft = null;
    });
    if (hadFocus && !_controlsVisible) _focusIdleOrOverlay();
  }

  void _dismissUpNext() {
    _upNextDismissed = true;
    _hideUpNext();
    if (_ended) unawaited(_exit());
  }

  Future<void> _pickSleepTimer() async {
    final deadline = _sleepDeadline;
    final remaining = deadline == null ? null : sleepTimerRemaining(deadline, DateTime.now());
    // 0 = off; null = sheet dismissed.
    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: PrairieColors.bgElevated,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Off', style: TextStyle(color: PrairieColors.ink)),
              subtitle: remaining == null
                  ? null
                  : Text('${formatSleepCountdown(remaining)} left', style: const TextStyle(color: PrairieColors.muted)),
              trailing: remaining == null ? const Icon(Icons.check, color: PrairieColors.amber) : null,
              onTap: () => Navigator.of(context).pop<int>(0),
            ),
            for (final minutes in sleepTimerPresets)
              ListTile(
                title: Text(sleepTimerLabel(minutes), style: const TextStyle(color: PrairieColors.ink)),
                onTap: () => Navigator.of(context).pop<int>(minutes),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 0) {
      _sleepTicker?.cancel();
      setState(() => _sleepDeadline = null);
      return;
    }
    _startSleepTicker(DateTime.now().add(Duration(minutes: choice)));
    _notify('Sleep timer set for ${sleepTimerLabel(choice)}');
  }

  /// Wall-clock countdown: keeps running while paused and across auto-played
  /// episodes (the deadline rides along in [PlayerLaunch.sleepDeadline]).
  void _startSleepTicker(DateTime deadline) {
    _sleepTicker?.cancel();
    _sleepDeadline = deadline;
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final current = _sleepDeadline;
      if (current != null && sleepTimerRemaining(current, DateTime.now()) == null) {
        _onSleepTimerFired();
      } else if (_controlsVisible) {
        // The countdown chip only shows with the chrome.
        setState(() {});
      }
    });
    if (mounted) setState(() {});
  }

  /// Pauses (and stops any up next countdown); if the episode already ended
  /// and was counting down to the next one, leaves the player instead.
  void _onSleepTimerFired() {
    _sleepTicker?.cancel();
    setState(() => _sleepDeadline = null);
    if (_ended) {
      unawaited(_exit());
      return;
    }
    _viewerPaused = true;
    unawaited(_backend?.pause());
    if (_upNextVisible) _hideUpNext();
    _showControls(focusPlay: true);
    _notify('Sleep timer ended — paused');
  }

  /// End of the episode: start the next one right away when autoplay is on
  /// (unless the viewer already cancelled it) — the up-next countdown ran
  /// during the credits — otherwise leave the player. Never sit on the last
  /// frame.
  void _onPlaybackEnded() {
    if (_ended || _exiting || _switchingEpisode) return;
    _ended = true;
    _introPromptTimer?.cancel();
    _introPrompt = null;
    final next = _nextEpisode;
    if (next != null && (_skip?.autoPlayNext ?? true) && !_upNextDismissed) {
      unawaited(_backend?.pause());
      unawaited(_playEpisode(next));
      return;
    }
    unawaited(_exit());
  }

  /// Some streams neither raise completion nor tick up to the source runtime
  /// (the plan's duration runs a few seconds past the last frame), so the
  /// position just freezes near the end. Treat that as the end, unless the
  /// viewer paused.
  void _checkEndStall() {
    if (_loading || _exiting || _ended || _switchingEpisode || _recovering || _error != null) return;
    if (_viewerPaused || _scrubTarget != null || _pendingReanchorSeek != null) return;
    final total = _sourceDurationSeconds;
    final lastAt = _lastProgressAt;
    if (total == null || lastAt == null) return;
    if (_position.inMilliseconds / 1000.0 < total - _endStallWindowSeconds) return;
    if (DateTime.now().difference(lastAt) < _endStallTimeout) return;
    _onPlaybackEnded();
  }

  /// Replaces this player with one for [episode], stopping the current
  /// session first so the two never hold the decoder at once.
  Future<void> _playEpisode(EpisodeRef episode) async {
    if (_switchingEpisode || _exiting) return;
    _switchingEpisode = true;
    _upNextTimer?.cancel();
    setState(() => _loading = true);
    try {
      final watch = await fetchWatchDetail(ref.read(apiClientProvider), ref.read(sessionProvider)!, episode.contentId);
      final fileId = selectPlaybackFileId(watch);
      if (fileId == null) throw StateError('No playable file for ${episode.code}');
      if (!mounted || _exiting) return;
      await _exit(
        to: PlayerRoute(
          launch: PlayerLaunch(
            fileId: fileId,
            title: watch.title.isNotEmpty ? watch.title : episode.title,
            contentId: episode.contentId,
            startPositionSeconds: resumePositionSeconds(watch.userData?.positionSeconds, watch.userData?.durationSeconds) ?? 0.0,
            watch: watch,
            // Keep the viewer's subtitle choice; audio is per file.
            initialSubtitleLanguage: widget.launch.initialSubtitleLanguage,
            sleepDeadline: _sleepDeadline,
          ),
          back: widget.back,
        ),
      );
    } catch (e, stack) {
      debugPrint('prairie.player_screen: _playEpisode failed: $e\n$stack');
      if (!mounted || _exiting) return;
      _switchingEpisode = false;
      if (_ended) {
        unawaited(_exit());
        return;
      }
      setState(() => _loading = false);
      _notify('Could not start ${episode.code}');
    }
  }

  Future<void> _togglePlayPause() async {
    final backend = _backend;
    if (backend == null) return;
    if (backend.isPlaying) {
      _viewerPaused = true;
      await backend.pause();
    } else {
      _viewerPaused = false;
      await backend.play();
      // Resuming after a pause: `_lastProgressAt` was frozen at pause time
      // (no position-stream tick fires while paused), so without this the
      // stall check could fire on the very next 2s tick even though playback
      // just resumed and hasn't had a chance to advance yet.
      _lastProgressAt = DateTime.now();
    }
    _showControls();
    setState(() {});
  }

  Future<void> _seekBy(Duration delta) => _seekToPosition(_position + delta);

  /// Total media duration for display/clamping. Prefers the session's own
  /// [PlaybackSessionResponse.durationSeconds] (the original file's actual
  /// runtime, stable across reattaches) over the backend's own reported
  /// duration — for remux, each reattach-at-a-new-position pipes from a
  /// fresh `-ss` offset to EOF, so the native player's own duration is only
  /// the *remaining* runtime from that anchor, not the total. Falls back to
  /// the backend when the session doesn't know the duration up front.
  Duration? get _totalDuration {
    final sessionSeconds = _playbackSession?.durationSeconds;
    if (sessionSeconds != null && sessionSeconds > 0) {
      return Duration(milliseconds: (sessionSeconds * 1000).round());
    }
    return _backend?.duration;
  }

  /// Media time the current transport has produced up to, as far as the TV
  /// player can tell (it exposes no seekable ranges): the native duration of
  /// a growing playlist, or at least the last position it actually played.
  double _producedEndSeconds() {
    final played = _lastProgressPosition.inMilliseconds / 1000.0;
    final native = _backend?.duration;
    if (native == null || native <= Duration.zero) return played;
    final produced = (_streamOrigin + native).inMilliseconds / 1000.0;
    return produced > played ? produced : played;
  }

  /// Seeks against the plan timeline, like VideoPlayer.tsx's
  /// `performPlayerSeek`:
  /// - inside the transport's seek window (or anywhere, when the plan says
  ///   `can_seek_anywhere`) the native player seeks in place, in player time
  ///   (media time − the timeline offset);
  /// - outside it, a `seek_reanchor` replan opens a fresh transport at the
  ///   target — only when the server negotiated `seek_reanchor_v1`.
  ///
  /// Progressive remux is always a re-anchor: it is copy-mode video piped
  /// live with no Range support, and `video_player_videohole` throws
  /// `PlatformException(SeekTo, Player seek to failed, ...)` for it
  /// unconditionally (confirmed on-device), so a native seek is never tried.
  /// A native seek that fails elsewhere also falls back to a re-anchor.
  ///
  /// Re-anchoring is expensive (network round trip, fresh transport, a new
  /// `initialize()`), so it is debounced: the displayed position updates on
  /// every call for responsive feedback, and the replan fires once input
  /// pauses, using the latest target.
  ///
  /// [revealChrome] false keeps the controls hidden — automatic marker skips
  /// shouldn't pop the whole transport up.
  Future<void> _seekToPosition(Duration target, {bool revealChrome = true}) async {
    final backend = _backend;
    if (backend == null || _recovering) return;
    final generation = ++_seekGeneration;
    final duration = _totalDuration ?? Duration.zero;
    var next = target < Duration.zero ? Duration.zero : target;
    if (duration > Duration.zero && next > duration) next = duration;

    final plan = _playbackSession;
    final canReanchor = plan?.supportsSeekReanchor ?? false;
    final isRemux = (plan?.playMethod ?? '').trim().toLowerCase() == 'remux';
    final targetSeconds = next.inMilliseconds / 1000.0;
    final timeline = plan?.timeline;
    final outsideWindow = timeline != null &&
        !timeline.canSeekLocally(targetSeconds, producedEndSeconds: _producedEndSeconds());
    if (canReanchor && (isRemux || outsideWindow || next < _streamOrigin)) {
      _scheduleReanchor(next, revealChrome: revealChrome);
      return;
    }

    final nativeTarget = next - _streamOrigin;
    try {
      await backend.seekTo(nativeTarget < Duration.zero ? Duration.zero : nativeTarget);
      if (mounted) {
        _showSeekPreview(next);
        setState(() => _position = next);
      }
      unawaited(_reportSeekLanding(backend, next, plan?.playMethod, generation));
    } on PlatformException catch (err) {
      debugPrint('prairie.player_screen: native seekTo failed: $err');
      backend.reportDiagnostic('seek:failed:${plan?.playMethod}:${err.message ?? err.code}');
      if (canReanchor) {
        _scheduleReanchor(next, revealChrome: revealChrome);
        return;
      }
    }
    if (revealChrome) _showControls();
  }

  /// Records where a native seek actually landed, for the stats overlay and
  /// diagnostics beacon: ±15s has been seen landing 3–4s short on-device.
  /// The first tick after a seek can still carry the pre-seek position, so
  /// the second is the one reported, along with how long after the seek it
  /// arrived (playback keeps advancing in the meantime).
  Future<void> _reportSeekLanding(VideoBackend backend, Duration target, String? playMethod, int generation) async {
    final seekedAt = DateTime.now();
    Duration landed;
    try {
      landed = await backend.positionStream.skip(1).first.timeout(const Duration(seconds: 5));
    } catch (_) {
      return;
    }
    if (!mounted || !identical(_backend, backend) || generation != _seekGeneration) return;
    final absolute = _streamOrigin + landed;
    backend.reportDiagnostic(
      'seek:landed:$playMethod:want=${target.inMilliseconds}:got=${absolute.inMilliseconds}'
      ':after=${DateTime.now().difference(seekedAt).inMilliseconds}',
    );
  }

  void _scheduleReanchor(Duration next, {bool revealChrome = true}) {
    _showSeekPreview(next);
    setState(() => _position = next);
    if (revealChrome) _showControls();
    _pendingReanchorSeek = next;
    _seekDebounce?.cancel();
    _seekDebounce = Timer(_seekDebounceDelay, () {
      final pending = _pendingReanchorSeek;
      _pendingReanchorSeek = null;
      if (pending == null || !mounted) return;
      final audioIndex = _playbackSession?.audioTrackIndex ?? 0;
      unawaited(_restartSessionAt(audioTrackIndex: audioIndex, positionSeconds: pending.inMilliseconds / 1000.0));
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _playerMetaLine(bool isPlaying) {
    final bits = <String>['TV player'];
    final method = _playbackSession?.playMethod;
    if (method == 'direct') bits.add('Direct');
    if (method == 'remux') bits.add('Remux');
    if (method == 'transcode') bits.add('Transcode');
    String? qualityLabel;
    for (final opt in _qualityOptions) {
      if (opt.id == _activeQualityId) {
        qualityLabel = opt.label;
        break;
      }
    }
    if (qualityLabel != null) bits.add(qualityLabel);
    if (_busyQuality) bits.add('Switching…');
    if (!isPlaying) bits.add('Paused');
    return bits.join(' · ');
  }

  /// "Stats for nerds" — read directly off the backend each build (piggybacks
  /// on the once-a-second rebuild [_positionSub] already drives) rather than
  /// wiring up dedicated diagnostics streams for a debug-only overlay.
  Widget _buildStatsOverlay(VideoBackend backend) {
    final session = _playbackSession;
    final watch = widget.launch.watch;
    final version = watch == null || session == null ? null : selectFileVersion(watch, session.mediaFileId);
    final audioIndex = session?.audioTrackIndex;
    final audioTracks = version?.audioTracks ?? const <AudioTrackInfo>[];
    final audioLabel = audioIndex != null && audioIndex >= 0 && audioIndex < audioTracks.length
        ? formatAudioLabel(audioTracks[audioIndex], audioIndex)
        : null;
    final diagnostics = backend.recentDiagnostics;
    final lines = [
      'session: ${session?.sessionId ?? '—'}',
      'playMethod: ${session?.playMethod ?? '—'}  quality: $_activeQualityId',
      'plan: ${session?.planSummary ?? '—'}',
      'audio: ${audioIndex ?? '—'}${audioLabel != null ? ' · $audioLabel' : ''}',
      'stream: ${_attachedStreamPath ?? '—'}',
      'isInitialized: ${backend.isInitialized}',
      'isPlaying: ${backend.isPlaying}',
      'isBuffering: ${backend.isBuffering}',
      'position: ${_formatDuration(_position)} / ${_formatDuration(_totalDuration ?? Duration.zero)}',
      'streamOrigin: ${_formatDuration(_streamOrigin)}',
      if (_error != null) 'error: $_error',
      if (diagnostics.isNotEmpty) '— player events —',
      for (final event in diagnostics.length > 8 ? diagnostics.sublist(diagnostics.length - 8) : diagnostics) event,
    ];
    return Positioned(
      top: 24,
      left: 24,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ConstrainedBox(
            // Plan summaries and player events run long; wrap them rather than
            // letting them run off the panel.
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines)
                  Text(line, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backend = _backend;
    // Directional mode lets arrow keys leave widgets that don't claim them.
    // Material Slider in traditional mode eats Down as "decrease", which is
    // why D-pad Down on the seek bar never reached the transport buttons.
    final media = MediaQuery.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // First Back dismisses the overlay chrome; only exits the stream
        // when it's already hidden — mirrors [_onIdleKey]'s Back/Escape
        // bubble-through, which only applies once idle focus already owns
        // the key (i.e. controls are already hidden).
        if (_controlsVisible) {
          _hideControlsNow();
        } else {
          _exit();
        }
      },
      child: MediaQuery(
        data: media.copyWith(navigationMode: NavigationMode.directional),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            focusNode: _idleFocus,
            skipTraversal: true,
            onKeyEvent: _onIdleKey,
            child: GestureDetector(
              onTap: () => _showControls(focusPlay: true),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (backend != null) backend.buildSurface(),
                  PlayerScrim(loading: _loading && _error == null, chromeVisible: _controlsVisible),
                  if (_showStats && backend != null) _buildStatsOverlay(backend),
                  if (_caption != null && _caption!.text.isNotEmpty)
                    Align(
                      alignment: switch (_caption!.verticalPosition) {
                        SubtitleVerticalPosition.top => Alignment.topCenter,
                        SubtitleVerticalPosition.middle => Alignment.center,
                        SubtitleVerticalPosition.bottom =>
                          Alignment(0, 1 - 2 * subtitleAppearanceBottomFraction(_subtitleAppearance)),
                      },
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          32,
                          _caption!.verticalPosition == SubtitleVerticalPosition.top ? 32 : 0,
                          32,
                          0,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: subtitleAppearanceBackgroundColor(_subtitleAppearance),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: Text(_caption!.text, textAlign: TextAlign.center, style: subtitleAppearanceTextStyle(_subtitleAppearance)),
                          ),
                        ),
                      ),
                    ),
                  if (_loading) const Center(child: PrairieLoadingIndicator()),
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
                          // Autofocus: this button mounts fresh the moment an
                          // error occurs, at which point the transport row
                          // (holding whatever previously had focus) has just
                          // been removed from the tree — without this, focus
                          // has nowhere reliable to land and the D-pad OK
                          // button does nothing, stranding the viewer on the
                          // error screen.
                          ElevatedButton(autofocus: true, onPressed: _exit, child: const Text('Back')),
                        ],
                      ),
                    ),
                  if (_controlsVisible && backend != null && !_loading && _error == null)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.72),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.88),
                            ],
                            stops: const [0.0, 0.22, 0.62, 1.0],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextButton.icon(
                                      focusNode: _backFocus,
                                      onPressed: _exit,
                                      style: TextButton.styleFrom(
                                        foregroundColor: PrairieColors.ink,
                                        backgroundColor: const Color(0x590A0C10),
                                        padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                                        shape: const StadiumBorder(),
                                      ),
                                      icon: const Icon(Icons.arrow_back, size: 18),
                                      label: const Text('Back', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'NOW PLAYING',
                                            style: TextStyle(color: PrairieColors.amber, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                                          ),
                                          Text(
                                            widget.launch.title?.trim().isNotEmpty == true
                                                ? widget.launch.title!
                                                : 'File ${widget.launch.fileId}',
                                            style: const TextStyle(fontFamily: 'Fraunces', fontSize: 24, color: PrairieColors.ink),
                                          ),
                                          Text(
                                            _playerMetaLine(backend.isPlaying),
                                            style: const TextStyle(color: PrairieColors.muted, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_sleepDeadline case final deadline?)
                                      if (sleepTimerRemaining(deadline, DateTime.now()) case final left?)
                                        Chip(
                                          avatar: const Icon(Icons.bedtime, size: 18, color: PrairieColors.amber),
                                          label: Text(formatSleepCountdown(left)),
                                          labelStyle: const TextStyle(color: PrairieColors.ink, fontFeatures: [FontFeature.tabularFigures()]),
                                          backgroundColor: const Color(0x590A0C10),
                                          side: BorderSide.none,
                                          shape: const StadiumBorder(),
                                        ),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  widget.launch.title ?? '',
                                  style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, color: PrairieColors.ink),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(_formatDuration(_position), style: const TextStyle(color: PrairieColors.muted)),
                                    Expanded(child: _buildSeekBarWithPreview(backend)),
                                    Text(_formatDuration(_totalDuration ?? Duration.zero), style: const TextStyle(color: PrairieColors.muted)),
                                  ],
                                ),
                                PlayerTransportCluster(
                                  playFocus: _playFocus,
                                  isPlaying: backend.isPlaying,
                                  onPlayPause: _togglePlayPause,
                                  skipStep: _skipButtonStep,
                                  onSkipBack: () => _seekBy(-_skipButtonStep),
                                  onSkipForward: () => _seekBy(_skipButtonStep),
                                  onPreviousEpisode: _previousEpisode == null ? null : () => _playEpisode(_previousEpisode!),
                                  onNextEpisode: _nextEpisode == null ? null : () => _playEpisode(_nextEpisode!),
                                  trailing: [
                                    if (_audioTracks.length > 1)
                                      IconButton(
                                        iconSize: 28,
                                        style: playerTransportStyle(_busyAudio ? PrairieColors.muted : PrairieColors.ink),
                                        onPressed: _busyAudio || _busyQuality ? null : _pickAudioTrack,
                                        icon: const Icon(Icons.audiotrack),
                                        tooltip: 'Audio',
                                      ),
                                    if (backend.subtitleTracks.isNotEmpty)
                                      IconButton(
                                        iconSize: 28,
                                        style: playerTransportStyle(_selectedSubtitleTrackId != null ? PrairieColors.amber : PrairieColors.ink),
                                        onPressed: _busyQuality ? null : _pickSubtitleTrack,
                                        icon: const Icon(Icons.closed_caption),
                                        tooltip: 'Subtitles',
                                      ),
                                    if (_qualityOptions.isNotEmpty)
                                      IconButton(
                                        iconSize: 28,
                                        style: playerTransportStyle(
                                          _busyQuality
                                              ? PrairieColors.muted
                                              : (_activeQualityId != 'original' ? PrairieColors.amber : PrairieColors.ink),
                                        ),
                                        onPressed: _busyQuality || _busyAudio ? null : _pickQuality,
                                        icon: const Icon(Icons.high_quality),
                                        tooltip: 'Quality',
                                      ),
                                    IconButton(
                                      iconSize: 28,
                                      style: playerTransportStyle(_sleepDeadline != null ? PrairieColors.amber : PrairieColors.ink),
                                      onPressed: _pickSleepTimer,
                                      icon: const Icon(Icons.bedtime),
                                      tooltip: 'Sleep timer',
                                    ),
                                    IconButton(
                                      iconSize: 28,
                                      style: playerTransportStyle(_showStats ? PrairieColors.amber : PrairieColors.ink),
                                      onPressed: () => setState(() => _showStats = !_showStats),
                                      icon: const Icon(Icons.query_stats),
                                      tooltip: 'Stats for nerds',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (backend != null && _error == null) _buildMarkerOverlay(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Skip Intro / Watch Intro / Skip Recap·Credits·Preview pill, or the up
  /// next card, bottom right — above the transport while it is showing.
  Widget _buildMarkerOverlay() {
    Widget? child;
    final next = _nextEpisode;
    final intro = _introPrompt;
    final manual = _manualSkipRegion;
    if (_upNextVisible && next != null) {
      child = PlayerUpNextCard(
        episodeCode: next.code,
        title: next.title,
        secondsLeft: _upNextSecondsLeft,
        playFocus: _overlayFocus,
        onPlayNow: () => _playEpisode(next),
        onDismiss: _dismissUpNext,
      );
    } else if (intro != null) {
      child = PlayerSkipButton(
        label: _introPromptIsUndo ? 'Watch Intro' : 'Skip Intro',
        caption: _introPromptIsUndo ? 'Intro skipped' : null,
        focusNode: _overlayFocus,
        onPressed: _onIntroPromptPressed,
      );
    } else if (manual != null && !_loading) {
      child = PlayerSkipButton(
        label: switch (manual.kind) {
          MarkerKind.recap => 'Skip Recap',
          MarkerKind.credits => 'Skip Credits',
          _ => 'Skip Preview',
        },
        focusNode: _overlayFocus,
        onPressed: () {
          _resolvedMarkers.add(manual.key);
          _skipTo(manual.end);
        },
      );
    }
    if (child == null) return const SizedBox.shrink();
    return Positioned(
      right: 48,
      bottom: _controlsVisible ? 168 : 56,
      child: child,
    );
  }

  /// TV-friendly seek control: own FocusNode claims Left/Right as scrubs
  /// (see [playerSeekHoldStep]) and Down/Up as focus moves. The Material
  /// [Slider] is excluded from focus so it can't swallow D-pad with its
  /// 5%-of-duration keyboard steps.
  Widget _buildSeekBarWithPreview(VideoBackend backend) {
    final duration = _totalDuration ?? Duration.zero;
    final preview = _seekPreviewTime;
    final previewSeconds = preview?.inMilliseconds ?? (_scrubTarget ?? _position).inMilliseconds;
    final pct = duration.inMilliseconds > 0
        ? (previewSeconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final tile = preview == null
        ? null
        : resolveTrickplayTile(_activeTrickplay, preview.inMilliseconds / 1000.0);
    final serverUrl = ref.read(sessionProvider)?.serverUrl ?? '';

    // The Slider insets its track by the overlay radius on each side (see
    // [_buildSeekBar]'s theme), so the thumb travels that inset range, not the
    // full width.
    final trackInset = _seekFocus.hasFocus ? 18.0 : 14.0;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (preview != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: CustomSingleChildLayout(
              delegate: _SeekPreviewLayout(fraction: pct.toDouble(), trackInset: trackInset),
              child: _SeekPreviewBubble(
                timeLabel: _formatDuration(preview),
                tile: tile,
                serverUrl: serverUrl,
              ),
            ),
          ),
        _buildSeekBar(backend),
      ],
    );
  }

  Widget _buildSeekBar(VideoBackend backend) {
    final maxMs = (_totalDuration ?? const Duration(seconds: 1))
        .inMilliseconds
        .toDouble()
        .clamp(1.0, double.infinity)
        .toDouble();
    final value = (_scrubTarget ?? _position).inMilliseconds.toDouble().clamp(0.0, maxMs).toDouble();
    return Focus(
      focusNode: _seekFocus,
      onKeyEvent: _onSeekKey,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: focused ? 6 : 4,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: focused ? 10 : 8),
              overlayShape: RoundSliderOverlayShape(overlayRadius: focused ? 18 : 14),
              activeTrackColor: PrairieColors.amber,
              inactiveTrackColor: PrairieColors.muted.withValues(alpha: 0.35),
              thumbColor: PrairieColors.amberBright,
              overlayColor: PrairieColors.amber.withValues(alpha: 0.25),
            ),
            child: ExcludeFocus(
              child: Slider(
                value: value,
                max: maxMs,
                onChanged: (v) {
                  final next = Duration(milliseconds: v.round());
                  _scheduleHideControls();
                  _showSeekPreview(next);
                  setState(() => _position = next);
                },
                onChangeEnd: (v) => _seekToPosition(Duration(milliseconds: v.round())),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Centers the seek preview on the slider thumb, whatever the bubble's width
/// (a bare timecode is far narrower than a trickplay tile), and keeps it
/// inside the bar at either end.
class _SeekPreviewLayout extends SingleChildLayoutDelegate {
  const _SeekPreviewLayout({required this.fraction, required this.trackInset});

  final double fraction;
  final double trackInset;

  @override
  Size getSize(BoxConstraints constraints) => Size(constraints.maxWidth, _height);

  // The bubble's height is only known once laid out; the row reserves none,
  // because the bubble floats above the bar.
  static const _height = 0.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(maxWidth: constraints.maxWidth);

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(seekPreviewLeft(size.width, childSize.width, fraction, trackInset), -childSize.height);

  @override
  bool shouldRelayout(_SeekPreviewLayout oldDelegate) => oldDelegate.fraction != fraction || oldDelegate.trackInset != trackInset;
}

/// Seek scrub preview: optional trickplay tile + timecode, matching web SeekBar.
class _SeekPreviewBubble extends StatelessWidget {
  const _SeekPreviewBubble({
    required this.timeLabel,
    required this.tile,
    required this.serverUrl,
  });

  final String timeLabel;
  final TrickplayTilePreview? tile;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    final tip = tile;
    double? displayW;
    double? displayH;
    if (tip != null && tip.width > 0 && tip.height > 0) {
      displayW = math.min(tip.width.toDouble(), 176.0);
      displayH = displayW * tip.height / tip.width;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF2171717),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tip != null && displayW != null && displayH != null)
                  SizedBox(
                    width: displayW,
                    height: displayH,
                    child: ColoredBox(
                      color: Colors.black,
                      child: ClipRect(
                        child: OverflowBox(
                          maxWidth: displayW * tip.columns,
                          maxHeight: displayH * tip.rows,
                          alignment: Alignment(tip.alignmentX, tip.alignmentY),
                          child: SizedBox(
                            width: displayW * tip.columns,
                            height: displayH * tip.rows,
                            child: Image.network(
                              resolveAssetUrl(serverUrl, tip.url),
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    timeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Label for a native player subtitle track. Rejects codec-like language
/// values (e.g. `HDMV_PGS_SUBTITLE`) in favor of a numbered fallback.
String _nativeSubtitleLabel(String language, int index) {
  return formatSubtitleLabel(language: language, index: index);
}
