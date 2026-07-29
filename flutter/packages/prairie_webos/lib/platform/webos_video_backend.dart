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
  VideoPlayerController? _controller;
  final _positionController = StreamController<Duration>.broadcast();
  final _captionController = StreamController<String?>.broadcast();
  Timer? _positionTimer;
  List<SubtitleTrackChoice> _subtitleTracks = [];
  String? _lastCaptionText;
  bool _initialized = false;

  static bool _isHls(String url) {
    final path = url.split('?').first.toLowerCase();
    return path.endsWith('.m3u8') || path.contains('/hls') || path.contains('master.m3u8');
  }

  @override
  void attach(String url, {String? maxResolution}) {
    // maxResolution is accepted for VideoBackend parity with Tizen AVPlay
    // FIXED_MAX_RESOLUTION; video_player_drm has no equivalent adaptive hint yet.
    final hls = _isHls(url);
    final controller = VideoPlayerController.network(
      Uri.parse(url),
      formatHint: hls ? VideoFormat.hls : null,
    );
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
  }
}
