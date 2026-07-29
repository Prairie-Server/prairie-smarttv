import 'package:flutter/widgets.dart';

/// A selectable text/subtitle track, as reported by the native player.
/// Deliberately minimal (just enough to label a picker) — richer per-track
/// metadata belongs in the server-driven [SubtitleTrackInfo] instead.
class SubtitleTrackChoice {
  const SubtitleTrackChoice({required this.trackId, required this.language});
  final int trackId;
  final String language;
}

/// Platform-agnostic contract for video playback, implemented per platform
/// (Tizen via `video_player_avplay`, webOS via its own native path).
///
/// Mirrors the capability surface of src/platform/tizen/avplay.ts and
/// src/player/*. DRM configuration is a known gap — see the Tizen
/// implementation's TODOs.
///
/// Lifecycle (Tizen hole-punch requires the surface in the tree before
/// native prepare completes):
/// 1. [attach] — create the native controller (sync)
/// 2. mount [buildSurface] via setState
/// 3. [initialize] — await first frame / duration
/// 4. [play] / seek / …
/// 5. [dispose]
abstract class VideoBackend {
  /// Creates the native player for [url] without waiting for prepare.
  /// After this returns, [buildSurface] is valid to mount.
  void attach(String url, {String? maxResolution});

  /// Completes once the first frame/duration is known. Must only be called
  /// after [attach], ideally after [buildSurface] has been laid out for at
  /// least one frame (Tizen AVPlay hole-punch).
  Future<void> initialize({Duration? startPosition});

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);

  /// Emits playback position roughly once per second, for progress
  /// reporting to the Prairie server. Mirrors the polling in PlayerScreen.
  Stream<Duration> get positionStream;

  /// Native / pipeline failures after [initialize] (dead HLS, decoder error).
  /// Without this, a server encode that dies mid-play leaves the UI buffering.
  Stream<String> get errorStream;

  Duration? get duration;
  bool get isPlaying;
  bool get isInitialized;

  /// Whether the native player is currently stalled waiting on data — surfaced
  /// for the in-player "stats for nerds" overlay, not used by playback logic.
  bool get isBuffering;

  /// Diagnostics-only, fire-and-forget report of a player-state event string
  /// (e.g. `'init:start:…'`). No-op unless the platform backend has a
  /// diagnostics channel wired up and the user opted into it — see Tizen's
  /// `AvplayVideoBackend` beacon, the only reachable logging on that TV.
  /// Exists on the interface so callers in `prairie_core` (which never sees
  /// the concrete backend type) can still instrument lifecycle moments the
  /// backend itself doesn't observe, like [initialize]'s own call site.
  void reportDiagnostic(String event);

  /// Text tracks the native player found in the current stream. Empty
  /// until after [initialize] resolves; may also be empty if the file has no
  /// embedded subtitles.
  List<SubtitleTrackChoice> get subtitleTracks;

  /// Selects a text track by id (from [subtitleTracks]), or `null` to turn
  /// subtitles off.
  Future<void> selectSubtitleTrack(int? trackId);

  /// Emits the subtitle text that should be on screen right now (`null`
  /// when nothing should be showing), driven by the native player's own
  /// subtitle decoding/timing.
  Stream<String?> get captionStream;

  /// The platform's native video-rendering widget (e.g. `video_player_avplay`'s
  /// `VideoPlayer`), so the shared `PlayerScreen` never needs to know which
  /// native player produced it. Valid after [attach].
  Widget buildSurface();

  /// Releases the native player session. Mirrors AVPlay's
  /// `close()`/session teardown on player exit — must be called before
  /// leaving the player screen so the TV's single hardware decoder is
  /// freed for the next playback.
  Future<void> dispose();
}

/// Supplies a fresh [VideoBackend] instance per playback session. Platform
/// apps override [videoBackendFactoryProvider] with their real
/// implementation (see prairie_tizen's `AvplayVideoBackend`) — `prairie_core`
/// only knows the interface, never the concrete native bridge.
///
/// [enableDiagnostics] mirrors `PlaybackSettings.enableDiagnosticsBeacon` at
/// the moment playback starts — platforms with a diagnostics beacon (Tizen)
/// use it to skip wiring one up at all when the user hasn't opted in.
typedef VideoBackendFactory = VideoBackend Function({bool enableDiagnostics});
