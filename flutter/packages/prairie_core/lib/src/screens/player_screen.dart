import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _progressIntervalMs = 10000;
/// D-pad Left/Right on the seek bar — fixed seconds, not Material Slider's
/// default 5% of runtime (which is several minutes on a feature film).
@visibleForTesting
const playerSeekBarStep = Duration(seconds: 10);
const _seekBarStep = playerSeekBarStep;
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
  Timer? _progressTimer;
  Timer? _hideControlsTimer;
  Timer? _stallTimer;
  /// Debounce for remux's restart-based seek — see [_seekToPosition].
  Timer? _seekDebounce;
  Duration? _pendingRemuxSeek;
  /// When the stream was attached; stall detection runs during prepare too.
  DateTime? _streamAttachedAt;
  bool _exiting = false;
  SubtitleAppearance _subtitleAppearance = const SubtitleAppearance();
  int? _selectedSubtitleTrackId;
  String? _caption;
  CancelToken? _prepareCancel;
  bool _busyAudio = false;
  bool _busyQuality = false;

  /// Session returned by `/playback/start` — kept so "Original" on a direct
  /// base can drop HLS and reattach the progressive stream_url.
  PlaybackSessionResponse? _basePlaybackSession;

  /// Active quality menu selection, keyed by id (`auto` / `original` / rung id).
  String _activeQualityId = 'original';
  /// Rung id of the encode currently playing under Auto (for advice dedupe).
  String? _autoPlayingRungId;
  List<QualityLadderRung> _qualityLadder = fallbackQualityLadder;
  String? _qualityError;

  /// Receives D-pad keys while chrome is hidden so nav can bring it back.
  final FocusNode _idleFocus = FocusNode(debugLabel: 'player.idle');
  final FocusNode _backFocus = FocusNode(debugLabel: 'player.back');
  final FocusNode _seekFocus = FocusNode(debugLabel: 'player.seek');
  final FocusNode _playFocus = FocusNode(debugLabel: 'player.play');

  @override
  void initState() {
    super.initState();
    _seekFocus.addListener(_onControlFocusChanged);
    _playFocus.addListener(_onControlFocusChanged);
    _backFocus.addListener(_onControlFocusChanged);
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
    _seekDebounce?.cancel();
    _seekFocus.removeListener(_onControlFocusChanged);
    _playFocus.removeListener(_onControlFocusChanged);
    _backFocus.removeListener(_onControlFocusChanged);
    _idleFocus.dispose();
    _backFocus.dispose();
    _seekFocus.dispose();
    _playFocus.dispose();
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
    setState(() => _controlsVisible = false);
    // Controls leave the tree with their FocusNodes — park focus on the
    // idle catcher so the next D-pad event has somewhere to land.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_controlsVisible) _idleFocus.requestFocus();
    });
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
    if (_controlsVisible) {
      _scheduleHideControls();
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      return KeyEventResult.ignored;
    }
    _showControls(focusPlay: true);
    return KeyEventResult.handled;
  }

  KeyEventResult _onSeekKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    _scheduleHideControls();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekBy(-_seekBarStep));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekBy(_seekBarStep));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _backFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

  int _deviceMaxHeight() {
    final maxRes = ref.read(tvCapabilitiesProvider).maxResolution;
    return resolveNativeHeight(maxRes, _qualityLadder);
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
  void _clearAudioBusyIfCurrent(CancelToken cancel) {
    if (!mounted || !identical(_prepareCancel, cancel)) return;
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

  Future<void> _applyAdvice(PlaybackQualityAdvice advice) async {
    if (_activeQualityId != 'auto' || _busyQuality || _exiting) return;
    if (advice.rungId.isEmpty || advice.rungId == _autoPlayingRungId) return;
    // Prefer the server-provided targets so we don't need a local ladder copy
    // to act — Advice carries resolution + bitrate for exactly this reason.
    if (advice.resolution.isNotEmpty && advice.bitrateKbps > 0) {
      await _switchQualityToTargets(
        menuId: 'auto',
        playingRungId: advice.rungId,
        resolution: advice.resolution,
        bitrateKbps: advice.bitrateKbps,
        copyVideo: false,
        fromAdvice: true,
      );
      return;
    }
    await _switchQuality(advice.rungId, fromAdvice: true);
  }

  Future<void> _switchQuality(String qualityId, {bool fromAdvice = false}) async {
    final current = _playbackSession;
    final base = _basePlaybackSession;
    if (current == null || base == null || _busyQuality || _busyAudio || _exiting) return;
    if (!fromAdvice && qualityId == _activeQualityId) return;

    final fileId = current.mediaFileId;
    final nativeHeight = _sourceHeightForFile(widget.launch.watch, fileId);
    final ladder = qualityLadderForSourceHeight(_qualityLadder, nativeHeight);
    final options = _qualityOptions;
    final deviceMax = _deviceMaxHeight();
    // Auto is capped by both source and device so we don't start a 4K encode
    // on a 1080p panel.
    final autoCap = nativeHeight > 0 && deviceMax > 0
        ? (nativeHeight < deviceMax ? nativeHeight : deviceMax)
        : (nativeHeight > 0 ? nativeHeight : deviceMax);
    final autoLadder = [
      for (final r in ladder)
        if (nativeHeight <= 0 || r.height < nativeHeight) r,
    ];
    final targets = resolveQualityTargets(
      qualityId: qualityId,
      options: options,
      playMethod: base.playMethod,
      ladder: qualityId == 'auto' ? (autoLadder.isEmpty ? ladder : autoLadder) : ladder,
      deviceMaxHeight: qualityId == 'auto' ? autoCap : deviceMax,
    );

    final playingRungId = qualityId == 'auto'
        ? bestAutoRung(autoLadder.isEmpty ? ladder : autoLadder, autoCap)?.id
        : (qualityId == 'original' ? null : qualityId);

    await _switchQualityToTargets(
      menuId: fromAdvice ? 'auto' : qualityId,
      playingRungId: playingRungId,
      resolution: targets?.resolution,
      bitrateKbps: targets?.bitrateKbps,
      copyVideo: targets?.copyVideo ?? false,
      dropToOriginalDirect: targets == null,
      fromAdvice: fromAdvice,
    );
  }

  Future<void> _switchQualityToTargets({
    required String menuId,
    String? playingRungId,
    String? resolution,
    int? bitrateKbps,
    bool copyVideo = false,
    bool dropToOriginalDirect = false,
    bool fromAdvice = false,
  }) async {
    final current = _playbackSession;
    final base = _basePlaybackSession;
    if (current == null || base == null || _busyQuality || _busyAudio || _exiting) return;

    setState(() {
      _busyQuality = true;
      _qualityError = null;
      // Advice steps the encode under Auto — the menu selection stays Auto so
      // further advice keeps applying. Manual picks commit the chosen id.
      if (!fromAdvice) _activeQualityId = menuId;
      _loading = true;
    });

    final cancel = CancelToken();
    _prepareCancel?.cancel();
    _prepareCancel = cancel;
    final position = _position.inMilliseconds / 1000.0;
    final fileId = current.mediaFileId;

    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final settings = await loadPlaybackSettings(SharedPreferencesAsync());
      final deviceCaps = applyAudioChannelOverride(
        applyAv1AdvertiseOverrides(
          ref.read(tvCapabilitiesProvider),
          forceAv1: settings.forceAv1,
          disableAv1: settings.disableAv1,
        ),
        is8KPanel: settings.is8KPanel,
      );

      // Direct-play Original: drop HLS and reattach the progressive stream.
      if (dropToOriginalDirect) {
        final prepared = await preparePlayableSession(
          client,
          session,
          base,
          position,
          sourceResolution: _sourceResolutionForFile(widget.launch.watch, fileId),
          maxResolution: deviceCaps.maxResolution,
          cancelToken: cancel,
        );
        if (!mounted || _exiting || cancel.isCancelled) {
          await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
          _clearQualityBusyIfCurrent(cancel);
          return;
        }
        final previousId = _activeSessionId;
        if (previousId != null && previousId != prepared.session.sessionId && previousId != base.sessionId) {
          unawaited(stopPlaybackSession(client, session, previousId).catchError((_) {}));
        }
        _autoPlayingRungId = null;
        await _attachPrepared(
          prepared: prepared,
          client: client,
          session: session,
          cancel: cancel,
          settings: settings,
          deviceCaps: deviceCaps,
          clearBusy: _clearQualityBusyIfCurrent,
        );
        return;
      }

      // Flutter sessions are legacy start/transcode — quality changes restart
      // the encode with the rung's resolution + bitrate (same as web). Protocol
      // v3 replan is the long-term path once this client adopts attempt IDs.
      final startFrom = PlaybackSessionResponse(
        sessionId: base.sessionId,
        mediaFileId: base.mediaFileId,
        playMethod: base.playMethod,
        position: position,
        isPaused: current.isPaused,
        streamUrl: base.streamUrl,
        audioTrackIndex: current.audioTrackIndex,
        durationSeconds: current.durationSeconds ?? base.durationSeconds,
        playbackInfo: current.playbackInfo ?? base.playbackInfo,
      );

      final prepared = await preparePlayableSession(
        client,
        session,
        startFrom,
        position,
        sourceResolution: _sourceResolutionForFile(widget.launch.watch, fileId),
        maxResolution: deviceCaps.maxResolution,
        targetResolution: resolution,
        targetBitrateKbps: bitrateKbps,
        copyVideo: copyVideo,
        forceTranscode: !copyVideo,
        cancelToken: cancel,
      );
      if (!mounted || _exiting || cancel.isCancelled) {
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _clearQualityBusyIfCurrent(cancel);
        return;
      }

      final previousId = _activeSessionId;
      if (previousId != null && previousId != prepared.session.sessionId && previousId != base.sessionId) {
        unawaited(stopPlaybackSession(client, session, previousId).catchError((_) {}));
      }

      _autoPlayingRungId = playingRungId;
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

  Future<void> _attachPrepared({
    required PreparedPlayback prepared,
    required ApiClient client,
    required PrairieSession session,
    required CancelToken cancel,
    required PlaybackSettings settings,
    required TvPlaybackCapabilities deviceCaps,
    required void Function([CancelToken?]) clearBusy,
  }) async {
    _activeSessionId = prepared.session.sessionId;
    await _positionSub?.cancel();
    await _captionSub?.cancel();
    await _errorSub?.cancel();
    _stallTimer?.cancel();
    final oldBackend = _backend;
    _backend = null;
    await oldBackend?.dispose();

    final backend = ref.read(videoBackendFactoryProvider)(enableDiagnostics: settings.enableDiagnosticsBeacon);
    backend.attach(
      prepared.streamUrl,
      maxResolution: deviceCaps.maxResolution,
      contentAspectRatio: contentAspectRatioForFile(widget.launch.watch, prepared.session.mediaFileId),
    );
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
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _exiting || cancel.isCancelled) {
      await backend.dispose();
      await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
      clearBusy(cancel);
      return;
    }

    await _initializeBackend(
      backend,
      startPosition: prepared.playerStartSeconds > 0
          ? Duration(milliseconds: (prepared.playerStartSeconds * 1000).round())
          : null,
      playMethod: prepared.session.playMethod,
    );
    await backend.play();
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
    unawaited(_autoSelectSubtitleTrack(backend, settings.preferredSubtitleLanguage));
    _showControls();
  }

  /// Restarts the active playback session at [audioTrackIndex] /
  /// [positionSeconds] via PATCH `/playback/{id}/audio` + a fresh
  /// [preparePlayableSession] — the same server round trip whether the
  /// track actually changes or not, since the endpoint's job is "give me a
  /// stream for this track starting at this position." Used both for
  /// explicit audio-track switches and, in [_seekToPosition], as the seek
  /// fallback for streams whose native player can't seek in place.
  Future<void> _restartSessionAt({required int audioTrackIndex, required double positionSeconds}) async {
    final current = _playbackSession;
    final sessionId = _activeSessionId ?? current?.sessionId;
    if (current == null || sessionId == null || _busyAudio || _busyQuality || _exiting) return;

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
      final deviceCaps = applyAudioChannelOverride(
        applyAv1AdvertiseOverrides(
          ref.read(tvCapabilitiesProvider),
          forceAv1: settings.forceAv1,
          disableAv1: settings.disableAv1,
        ),
        is8KPanel: settings.is8KPanel,
      );

      final position = positionSeconds < 0 ? 0.0 : positionSeconds;
      final updated = await switchPlaybackAudio(client, session, sessionId, audioTrackIndex, position);
      if (!mounted || _exiting || cancel.isCancelled) {
        _clearAudioBusyIfCurrent(cancel);
        return;
      }

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
        _clearAudioBusyIfCurrent(cancel);
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

      final backend = ref.read(videoBackendFactoryProvider)(enableDiagnostics: settings.enableDiagnosticsBeacon);
      backend.attach(
        prepared.streamUrl,
        maxResolution: deviceCaps.maxResolution,
        contentAspectRatio: contentAspectRatioForFile(widget.launch.watch, prepared.session.mediaFileId),
      );
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
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _exiting || cancel.isCancelled) {
        await backend.dispose();
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _clearAudioBusyIfCurrent(cancel);
        return;
      }

      // See the matching comment in [_start]: the stall timer must not start
      // until playback has actually begun, or it preempts [_initializeTimeout].
      await _initializeBackend(
        backend,
        startPosition: prepared.playerStartSeconds > 0
            ? Duration(milliseconds: (prepared.playerStartSeconds * 1000).round())
            : null,
        playMethod: prepared.session.playMethod,
      );
      await backend.play();
      if (!mounted || _exiting || cancel.isCancelled) {
        await backend.dispose();
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _clearAudioBusyIfCurrent(cancel);
        return;
      }

      setState(() {
        _loading = false;
        _busyAudio = false;
      });
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
      unawaited(_autoSelectSubtitleTrack(backend, settings.preferredSubtitleLanguage));
      _showControls();
    } catch (e, stack) {
      debugPrint('prairie.player_screen: _restartSessionAt failed: $e\n$stack');
      if (mounted && !_exiting) {
        setState(() {
          _error = e is ApiError ? e.message : 'Could not restart playback';
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
      final deviceCaps = applyAudioChannelOverride(
        applyAv1AdvertiseOverrides(
          ref.read(tvCapabilitiesProvider),
          forceAv1: settings.forceAv1,
          disableAv1: settings.disableAv1,
        ),
        is8KPanel: settings.is8KPanel,
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
          maxAudioChannels: deviceCaps.maxAudioChannels,
        ),
      );
      startedSessionId = started.sessionId;
      _activeSessionId = started.sessionId;
      _basePlaybackSession = started;
      prefetchQualityLadder(client, session);
      unawaited(
        fetchQualityLadder(client, session).then((ladder) {
          if (!mounted) return;
          setState(() => _qualityLadder = ladder.isEmpty ? fallbackQualityLadder : ladder);
        }),
      );

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
      final backend = ref.read(videoBackendFactoryProvider)(enableDiagnostics: settings.enableDiagnosticsBeacon);
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
        _subtitleAppearance = settings.subtitleAppearance;
        _streamOrigin = origin;
        _position = origin + Duration(milliseconds: (prepared.playerStartSeconds * 1000).round());
      });
      _streamAttachedAt = DateTime.now();
      await WidgetsBinding.instance.endOfFrame;

      if (!mounted || _exiting || cancel.isCancelled) {
        await backend.dispose();
        await stopPlaybackSession(client, session, prepared.session.sessionId).catchError((_) {});
        _activeSessionId = null;
        return;
      }

      // Initialize has its own [_initializeTimeout] budget (matched to the
      // upstream HLS-readiness wait) — the stall timer below must not start
      // until playback has actually begun, or it preempts that budget with a
      // much tighter one (see the "stall timer preempts initialize" bug this
      // fixed: the 20s stall check used to fire while a 90s-budgeted encode
      // was still legitimately starting up).
      await _initializeBackend(
        backend,
        startPosition: prepared.playerStartSeconds > 0
            ? Duration(milliseconds: (prepared.playerStartSeconds * 1000).round())
            : null,
        playMethod: prepared.session.playMethod,
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
      if (needsHlsBootstrap(prepared.session.playMethod)) {
        _stallTimer?.cancel();
        _stallTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkHlsStall());
      }
      _positionSub = backend.positionStream.listen((position) {
        if (!mounted) return;
        final absolute = _streamOrigin + position;
        if (absolute != _lastProgressPosition) {
          _lastProgressPosition = absolute;
          _lastProgressAt = DateTime.now();
        }
        setState(() => _position = absolute);
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
      unawaited(_autoSelectSubtitleTrack(backend, widget.launch.initialSubtitleLanguage ?? settings.preferredSubtitleLanguage));
      final initialAudio = widget.launch.initialAudioTrackIndex;
      if (initialAudio != null && initialAudio != (_playbackSession?.audioTrackIndex ?? 0)) {
        unawaited(_chooseAudio(initialAudio));
      }
    } catch (e) {
      if (startedSessionId != null && _activeSessionId == startedSessionId) {
        // Leave stop to the catch path only when we didn't already stop above.
      }
      if (mounted && !_exiting) {
        setState(() {
          _error = e is ApiError
              ? e.message
              : e is HlsProbeAuthError
                  ? 'Not authorized to play this stream. Try signing in again.'
                  : e is TranscodeStartupTimeoutError
                      ? e.message
                      : 'Playback failed: $e';
          _loading = false;
        });
      }
    }
  }

  void _checkHlsStall() {
    if (!mounted || _exiting || _error != null) return;
    final backend = _backend;
    if (backend == null) return;
    // The timer only ever starts after a successful `play()` (see [_start] /
    // [_chooseAudio]), so this is purely a post-start "stopped producing
    // media" detector — not a substitute for [_initializeTimeout]. A user
    // pause freezes `_lastProgressAt` (it only advances on a position-stream
    // tick), so a paused stream must not be judged stalled just for sitting
    // still — resuming refreshes `_lastProgressAt` in [_togglePlayPause].
    if (!backend.isPlaying) return;
    final lastAt = _lastProgressAt ?? _streamAttachedAt;
    if (lastAt == null) return;
    if (DateTime.now().difference(lastAt) < _hlsStallTimeout) return;
    setState(() {
      _error = 'Playback stalled — the stream stopped producing media.';
      _loading = false;
    });
    _stallTimer?.cancel();
  }

  Future<void> _initializeBackend(VideoBackend backend, {Duration? startPosition, String? playMethod}) async {
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
    final backend = _backend;
    final wantAdvice = _activeQualityId == 'auto' && !paused && !_busyQuality;
    try {
      final advice = await reportPlaybackProgress(
        ref.read(apiClientProvider),
        ref.read(sessionProvider)!,
        sessionId,
        _position.inSeconds.toDouble(),
        paused,
        isBuffering: backend?.isBuffering,
        requestAdvice: wantAdvice,
      );
      if (advice == null || !mounted || _exiting || _busyQuality) return;
      if (_activeQualityId != 'auto') return;
      // Honor automatic stepping while Auto is selected. Key on rung id so
      // High variants stay distinct from their same-height siblings.
      if (advice.rungId.isEmpty) return;
      unawaited(_applyAdvice(advice));
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
    _seekDebounce?.cancel();
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

  /// Remux is copy-mode video piped live over plain progressive HTTP with
  /// no in-place seek support at all — confirmed on-device:
  /// `video_player_videohole` throws `PlatformException(SeekTo, Player seek
  /// to failed, ...)` unconditionally for this content, both mid-playback
  /// and on resume-to-position. The server's stream handler instead reads a
  /// `?seek=` query param and respawns ffmpeg with `-ss` before `-i` — see
  /// [preparePlayableSession] — so every remux seek goes straight to a full
  /// session restart at the target position, without wasting a doomed
  /// native seekTo call first. Direct/transcode still try the cheap
  /// in-place native seek, which works for them.
  ///
  /// Restarting is expensive enough (network round trip, fresh ffmpeg, a new
  /// `initialize()`) that firing one per D-pad repeat tick or ±15s mash
  /// drops every seek after the first behind [_restartSessionAt]'s
  /// `_busyAudio` guard — the stream never advances past whatever the first
  /// tick asked for. Debounced: the displayed position updates immediately
  /// on every call for responsive visual feedback, but the actual restart
  /// only fires once input has paused, using the latest target.
  Future<void> _seekToPosition(Duration target) async {
    final backend = _backend;
    if (backend == null) return;
    final duration = _totalDuration ?? Duration.zero;
    var next = target < Duration.zero ? Duration.zero : target;
    if (duration > Duration.zero && next > duration) next = duration;

    final isRemux = (_playbackSession?.playMethod ?? '').trim().toLowerCase() == 'remux';
    if (isRemux) {
      setState(() => _position = next);
      _showControls();
      _pendingRemuxSeek = next;
      _seekDebounce?.cancel();
      _seekDebounce = Timer(_seekDebounceDelay, () {
        final pending = _pendingRemuxSeek;
        _pendingRemuxSeek = null;
        if (pending == null || !mounted) return;
        final audioIndex = _playbackSession?.audioTrackIndex ?? 0;
        unawaited(_restartSessionAt(audioTrackIndex: audioIndex, positionSeconds: pending.inMilliseconds / 1000.0));
      });
      return;
    }

    try {
      await backend.seekTo(next);
      if (mounted) setState(() => _position = next);
    } on PlatformException catch (err) {
      debugPrint('prairie.player_screen: native seekTo failed: $err');
    }
    _showControls();
  }

  /// Overrides the app theme's flat `IconButton`/`TextButton` foreground:
  /// passing a plain `color:` locks the icon/text color for every state,
  /// but the shared theme still flips these buttons' *background* to
  /// [PrairieColors.ink] on D-pad focus — combined, that made the
  /// audio/subtitle/stats controls (which pass `color: PrairieColors.ink`)
  /// paint an ink-colored icon on an ink-colored background when focused,
  /// i.e. invisible. This keeps [color] unfocused and flips to
  /// [PrairieColors.bg] focused, matching the background flip everywhere
  /// else in the app.
  ButtonStyle _transportForegroundStyle(Color color) => ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused) ? PrairieColors.bg : color,
    ),
  );

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
    final lines = [
      'session: ${_playbackSession?.sessionId ?? '—'}',
      'playMethod: ${_playbackSession?.playMethod ?? '—'}',
      'isInitialized: ${backend.isInitialized}',
      'isPlaying: ${backend.isPlaying}',
      'isBuffering: ${backend.isBuffering}',
      'position: ${_formatDuration(_position)} / ${_formatDuration(_totalDuration ?? Duration.zero)}',
      'streamOrigin: ${_formatDuration(_streamOrigin)}',
      if (_error != null) 'error: $_error',
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
                  if (_showStats && backend != null) _buildStatsOverlay(backend),
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
                                    Expanded(child: _buildSeekBar(backend)),
                                    Text(_formatDuration(_totalDuration ?? Duration.zero), style: const TextStyle(color: PrairieColors.muted)),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    TextButton(
                                      style: _transportForegroundStyle(PrairieColors.ink),
                                      onPressed: () => _seekBy(const Duration(seconds: -15)),
                                      child: const Text('-15s', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      focusNode: _playFocus,
                                      autofocus: true,
                                      iconSize: 48,
                                      style: _transportForegroundStyle(PrairieColors.amber),
                                      onPressed: _togglePlayPause,
                                      icon: Icon(backend.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      style: _transportForegroundStyle(PrairieColors.ink),
                                      onPressed: () => _seekBy(const Duration(seconds: 15)),
                                      child: const Text('+15s', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    ),
                                    if (_audioTracks.length > 1) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        iconSize: 28,
                                        style: _transportForegroundStyle(_busyAudio ? PrairieColors.muted : PrairieColors.ink),
                                        onPressed: _busyAudio || _busyQuality ? null : _pickAudioTrack,
                                        icon: const Icon(Icons.audiotrack),
                                        tooltip: 'Audio',
                                      ),
                                    ],
                                    if (backend.subtitleTracks.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        iconSize: 28,
                                        style: _transportForegroundStyle(_selectedSubtitleTrackId != null ? PrairieColors.amber : PrairieColors.ink),
                                        onPressed: _busyQuality ? null : _pickSubtitleTrack,
                                        icon: const Icon(Icons.closed_caption),
                                        tooltip: 'Subtitles',
                                      ),
                                    ],
                                    if (_qualityOptions.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        iconSize: 28,
                                        style: _transportForegroundStyle(
                                          _busyQuality
                                              ? PrairieColors.muted
                                              : (_activeQualityId != 'original' ? PrairieColors.amber : PrairieColors.ink),
                                        ),
                                        onPressed: _busyQuality || _busyAudio ? null : _pickQuality,
                                        icon: const Icon(Icons.high_quality),
                                        tooltip: 'Quality',
                                      ),
                                    ],
                                    const SizedBox(width: 8),
                                    IconButton(
                                      iconSize: 28,
                                      style: _transportForegroundStyle(_showStats ? PrairieColors.amber : PrairieColors.ink),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// TV-friendly seek control: own FocusNode claims Left/Right as fixed
  /// [_seekBarStep] seeks and Down/Up as focus moves. The Material [Slider]
  /// is excluded from focus so it can't swallow D-pad with its 5%-of-duration
  /// keyboard steps.
  Widget _buildSeekBar(VideoBackend backend) {
    final maxMs = (_totalDuration ?? const Duration(seconds: 1))
        .inMilliseconds
        .toDouble()
        .clamp(1.0, double.infinity)
        .toDouble();
    final value = _position.inMilliseconds.toDouble().clamp(0.0, maxMs).toDouble();
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
                  _scheduleHideControls();
                  setState(() => _position = Duration(milliseconds: v.round()));
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

/// Label for a native player subtitle track. Rejects codec-like language
/// values (e.g. `HDMV_PGS_SUBTITLE`) in favor of a numbered fallback.
String _nativeSubtitleLabel(String language, int index) {
  return formatSubtitleLabel(language: language, index: index);
}
