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
abstract class VideoBackend {
  /// Prepares playback of [url] and returns once the first frame/duration
  /// is known. Mirrors `createMediaPlayer`'s init step.
  Future<void> load(String url, {Duration? startPosition});

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);

  /// Emits playback position roughly once per second, for progress
  /// reporting to the Prairie server. Mirrors the polling in PlayerScreen.
  Stream<Duration> get positionStream;

  Duration? get duration;
  bool get isPlaying;

  /// Text tracks the native player found in the current stream. Empty
  /// until after [load] resolves; may also be empty if the file has no
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
  /// native player produced it. Only valid to call after [load] resolves.
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
typedef VideoBackendFactory = VideoBackend Function();
