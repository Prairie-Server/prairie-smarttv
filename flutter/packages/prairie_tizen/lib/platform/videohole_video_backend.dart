import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:video_player_videohole/video_player.dart';

/// [VideoBackend] implementation over `video_player_videohole`, wrapping
/// Tizen's system Media Player (`player.h` capi / MMPlayer).
///
/// Chosen over `video_player_avplay` (PlusPlayer) because the AVPlay plugin's
/// bundled GStreamer demuxer plugins (`libgsthls.so`, `libgstffmpeg.so`) hard
/// -link `libclearkey.so.0`, and loading that library fails with `Operation
/// not permitted` on retail-signed (non-partner-cert) builds — blocking
/// playback of *any* content, DRM or not. `video_player_videohole` calls
/// Tizen's standard `player_set_uri` directly and never touches that
/// dependency, so it works on a retail cert. Trade-off: this plugin has no
/// DRM support at all — fine, since Prairie never serves DRM content.
class VideoholeVideoBackend implements VideoBackend {
  /// Diagnostics-only: the TV has no reachable local logging (`developer.log`
  /// needs a VM service that a release build doesn't attach, and `debugPrint`
  /// needs an `sdb dlog` session at the TV). The server already logs full
  /// request query strings, so state changes ride a `dbg=` param on a request
  /// it already receives — read back from the server's own request log,
  /// timestamped and correlated with the playback session. Never let a
  /// beacon failure affect playback: every call is fire-and-forget. Both are
  /// null unless the user opted into `PlaybackSettings.enableDiagnosticsBeacon`.
  VideoholeVideoBackend({this.beaconClient, this.beaconServerUrl});

  final ApiClient? beaconClient;
  final String? Function()? beaconServerUrl;

  @override
  void reportDiagnostic(String event) {
    final client = beaconClient;
    final serverUrl = beaconServerUrl?.call();
    if (client == null || serverUrl == null || serverUrl.isEmpty) return;
    unawaited(_sendBeacon(client, serverUrl, event));
  }

  static Future<void> _sendBeacon(ApiClient client, String serverUrl, String event) async {
    try {
      await client.dio.get<void>(
        '$serverUrl/api/v1/settings/effective',
        queryParameters: {'keys': 'playback.auto_skip_intro', 'dbg': event},
      );
    } catch (_) {
      // Diagnostics must never affect playback.
    }
  }

  VideoPlayerController? _controller;
  final _positionController = StreamController<Duration>.broadcast();
  final _captionController = StreamController<String?>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  Timer? _positionTimer;
  List<SubtitleTrackChoice> _subtitleTracks = [];
  String? _lastCaptionText;
  String? _lastError;
  bool _initialized = false;
  bool? _lastBuffering;
  bool? _lastIsInitialized;

  /// Redacts query-param values (session tokens) before a URL hits the log.
  static String _redactQuery(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.query.isEmpty) return url;
    final redacted = {for (final key in uri.queryParameters.keys) key: '<redacted>'};
    return uri.replace(queryParameters: redacted).toString();
  }

  @override
  void attach(String url, {String? maxResolution}) {
    // video_player_videohole has no equivalent to AVPlay's fixed-max-resolution
    // knob (no DRM/ABR-cap parameter on the plugin's network constructor), so
    // maxResolution is accepted for interface parity but unused here.
    final controller = VideoPlayerController.network(url);

    final transport = isHlsUrl(url) ? 'hls' : 'progressive';
    debugPrint('prairie.videohole: attach url=${_redactQuery(url)} transport=$transport');
    reportDiagnostic('attach:backend=videohole:transport=$transport');

    _controller = controller;
    controller.addListener(_onControllerUpdate);
  }

  @override
  Future<void> initialize({Duration? startPosition}) async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('VideoholeVideoBackend.attach must be called before initialize');
    }
    await controller.initialize();
    _initialized = true;
    if (startPosition != null && startPosition > Duration.zero) {
      await controller.seekTo(startPosition);
    }
    try {
      final tracks = await controller.textTracks ?? const <TextTrack>[];
      _subtitleTracks = tracks
          .map((t) => SubtitleTrackChoice(trackId: t.trackId, language: t.language))
          .toList();
    } catch (_) {
      _subtitleTracks = [];
    }
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final position = _controller?.value.position;
      if (position != null) _positionController.add(position);
    });
  }

  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;

    if (value.isBuffering != _lastBuffering) {
      _lastBuffering = value.isBuffering;
      debugPrint('prairie.videohole: isBuffering=${value.isBuffering} position=${value.position} buffered=${value.buffered}');
      reportDiagnostic('buf=${value.isBuffering}:pos=${value.position.inMilliseconds}');
    }
    if (value.isInitialized != _lastIsInitialized) {
      _lastIsInitialized = value.isInitialized;
      debugPrint('prairie.videohole: isInitialized=${value.isInitialized} duration=${value.duration}');
      reportDiagnostic('init=${value.isInitialized}:dur=${value.duration.end.inMilliseconds}');
    }

    if (value.hasError) {
      final message = (value.errorDescription ?? 'Playback failed').trim();
      if (message.isNotEmpty && message != _lastError) {
        _lastError = message;
        debugPrint('prairie.videohole: hasError message=$message');
        reportDiagnostic('err=$message');
        if (!_errorController.isClosed) _errorController.add(message);
      }
    }

    final text = value.caption.text.isEmpty ? null : value.caption.text;
    if (text != _lastCaptionText) {
      _lastCaptionText = text;
      _captionController.add(text);
    }
  }

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isBuffering => _controller?.value.isBuffering ?? false;

  @override
  List<SubtitleTrackChoice> get subtitleTracks => _subtitleTracks;

  @override
  Future<void> selectSubtitleTrack(int? trackId) async {
    final controller = _controller;
    if (controller == null) return;
    if (trackId == null) {
      // Plugin has no explicit "off" — selecting nothing is a no-op; callers
      // clear the overlay caption themselves.
      return;
    }
    SubtitleTrackChoice? track;
    for (final t in _subtitleTracks) {
      if (t.trackId == trackId) {
        track = t;
        break;
      }
    }
    if (track == null) return;
    await controller.setTrackSelection(TextTrack(trackId: trackId, language: track.language));
  }

  @override
  Stream<String?> get captionStream => _captionController.stream;

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seekTo(Duration position) async => _controller?.seekTo(position);

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  Duration? get duration {
    final range = _controller?.value.duration;
    if (range == null) return null;
    final end = range.end;
    return end > Duration.zero ? end : null;
  }

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  Widget buildSurface() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    // Full-bleed surface: the native player's video plane needs a non-zero
    // laid-out size before prepare completes, same constraint as AVPlay's
    // hole-punch. AspectRatio(1.0) before init shrinks the hole and leaves
    // the Flutter loading spinner covering a blank plane.
    return SizedBox.expand(child: VideoPlayer(controller));
  }

  @override
  Future<void> dispose() async {
    _positionTimer?.cancel();
    final controller = _controller;
    _controller = null;
    _initialized = false;
    if (controller != null) {
      controller.removeListener(_onControllerUpdate);
      await controller.dispose();
    }
    if (!_positionController.isClosed) await _positionController.close();
    if (!_captionController.isClosed) await _captionController.close();
    if (!_errorController.isClosed) await _errorController.close();
  }
}
