import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:video_player_drm/video_player.dart';

/// [VideoBackend] implementation over `video_player_drm`, wrapping webOS's
/// native media pipeline (multi-audio, subtitles, DRM).
///
/// DRM (`drmConfigs` on `VideoPlayerController.network`) is supported by the
/// underlying plugin but not yet wired up here — same gap as Tizen AVPlay.
class WebosVideoBackend implements VideoBackend {
  /// Diagnostics-only: rides a `dbg=` param on a request the server already
  /// logs (see Tizen's `AvplayVideoBackend`, where this pattern started —
  /// same shape here so a support report from either platform ships the same
  /// way). Fire-and-forget; never let a beacon failure affect playback. Both
  /// are null unless the user opted into `PlaybackSettings.enableDiagnosticsBeacon`.
  WebosVideoBackend({this.beaconClient, this.beaconServerUrl});

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

  /// Same redaction as [_redactQuery], but for free-form text (plugin error
  /// descriptions) that may *embed* the failing URL rather than *be* one —
  /// native player errors routinely echo the URL they failed to open, query
  /// string (session token) and all.
  static final _embeddedUrlPattern = RegExp(r'https?://\S+');
  static String _redactMessage(String message) =>
      message.replaceAllMapped(_embeddedUrlPattern, (m) => _redactQuery(m.group(0)!));

  @override
  void attach(String url, {String? maxResolution}) {
    // maxResolution is accepted for VideoBackend parity with Tizen AVPlay
    // FIXED_MAX_RESOLUTION; video_player_drm has no equivalent adaptive hint yet.
    final hls = isHlsUrl(url);
    final controller = VideoPlayerController.network(
      Uri.parse(url),
      formatHint: hls ? VideoFormat.hls : null,
    );
    final queryParams = Uri.tryParse(url)?.queryParameters.keys.join(',');
    debugPrint('prairie.webos: attach url=${_redactQuery(url)} hls=$hls queryParams=$queryParams');
    reportDiagnostic('attach:hls=$hls:params=$queryParams');
    _controller = controller;
    controller.addListener(_onControllerUpdate);
  }

  @override
  Future<void> initialize({Duration? startPosition}) async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('WebosVideoBackend.attach must be called before initialize');
    }
    await controller.initialize();
    _initialized = true;
    if (startPosition != null && startPosition > Duration.zero) {
      await controller.seekTo(startPosition);
    }
    _refreshSubtitleTracks();
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final position = _controller?.value.position;
      if (position != null) _positionController.add(position);
    });
  }

  void _refreshSubtitleTracks() {
    final raw = _controller?.value.subtitleTracks;
    if (raw == null) {
      _subtitleTracks = [];
      return;
    }
    _subtitleTracks = [
      for (var i = 0; i < raw.length; i++)
        SubtitleTrackChoice(
          trackId: i,
          language: (raw[i]['language'] as String?)?.trim().isNotEmpty == true
              ? raw[i]['language'] as String
              : 'Track $i',
        ),
    ];
  }

  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;

    if (value.isBuffering != _lastBuffering) {
      _lastBuffering = value.isBuffering;
      debugPrint('prairie.webos: isBuffering=${value.isBuffering} position=${value.position}');
      reportDiagnostic('buf=${value.isBuffering}:pos=${value.position.inMilliseconds}');
    }
    if (value.isInitialized != _lastIsInitialized) {
      _lastIsInitialized = value.isInitialized;
      debugPrint('prairie.webos: isInitialized=${value.isInitialized} duration=${value.duration}');
      reportDiagnostic('init=${value.isInitialized}:dur=${value.duration.inMilliseconds}');
    }

    if (controller.value.hasError) {
      final message = (controller.value.errorDescription ?? 'Playback failed').trim();
      if (message.isNotEmpty && message != _lastError) {
        _lastError = message;
        final redacted = _redactMessage(message);
        debugPrint('prairie.webos: hasError message=$redacted');
        reportDiagnostic('err=$redacted');
        if (!_errorController.isClosed) _errorController.add(message);
      }
    }

    // Tracks often arrive after initialize via platform events.
    final incoming = controller.value.subtitleTracks;
    if (incoming != null && incoming.length != _subtitleTracks.length) {
      _refreshSubtitleTracks();
    }

    final text = controller.value.caption.text;
    final normalized = text.isEmpty ? null : text;
    if (normalized != _lastCaptionText) {
      _lastCaptionText = normalized;
      _captionController.add(normalized);
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
      await controller.setSubtitleEnabled(false);
      return;
    }
    await controller.setSubtitleEnabled(true);
    await controller.selectSubtitleTrack(trackId);
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
    final d = _controller?.value.duration;
    if (d == null || d <= Duration.zero) return null;
    return d;
  }

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  Widget buildSurface() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    // Full-bleed surface: webOS video plane shows through transparent Flutter
    // (appinfo.json transparent: true). Expand so the hole matches the screen.
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
