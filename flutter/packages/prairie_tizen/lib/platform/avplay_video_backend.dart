import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:video_player_avplay/video_player.dart';
import 'package:video_player_avplay/video_player_platform_interface.dart';

/// [VideoBackend] implementation over `video_player_avplay`, wrapping Tizen's
/// native AVPlay (MMPlayer/PlusPlayer) API.
///
/// DRM (`drmConfigs` on `VideoPlayerController.network`) is supported by the
/// underlying plugin but not yet wired up here.
class AvplayVideoBackend implements VideoBackend {
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
    final hls = _isHls(url);
    final fixed = avPlayFixedMaxResolution(maxResolution);
    final controller = VideoPlayerController.network(
      url,
      formatHint: hls ? VideoFormat.hls : null,
      streamingProperty: hls
          ? {
              StreamingPropertyType.adaptiveInfo: [
                'FIXED_MAX_RESOLUTION=$fixed',
                'STARTBITRATE=HIGHEST',
                'USER_AGENT=PrairieTizenClient',
                'INITIAL_BUFFER_DURATION=6000',
                'RESUME_BUFFER_DURATION=4000',
              ].join('|'),
              StreamingPropertyType.userAgent: 'PrairieTizenClient',
            }
          : {StreamingPropertyType.userAgent: 'PrairieTizenClient'},
    );
    _controller = controller;
    controller.addListener(_onControllerUpdate);
  }

  @override
  Future<void> initialize({Duration? startPosition}) async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('AvplayVideoBackend.attach must be called before initialize');
    }
    await controller.initialize();
    _initialized = true;
    if (startPosition != null && startPosition > Duration.zero) {
      await controller.seekTo(startPosition);
    }
    try {
      final tracks = await controller.getActiveTrackInfo();
      _subtitleTracks = tracks
          .where((t) => t.trackType == TrackType.text)
          .map((t) => SubtitleTrackChoice(trackId: t.trackId, language: (t as TextTrack).language))
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
    final captions = _controller?.value.captions;
    final text = captions?.textCaptions?.isNotEmpty == true ? captions!.textCaptions!.first.text : null;
    if (text != _lastCaptionText) {
      _lastCaptionText = text;
      _captionController.add(text);
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
    await controller.setTrackSelection(TextTrack(trackId: trackId, mimetype: '', language: track.language));
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
    // Full-bleed surface: Tizen hole-punch needs a non-zero laid-out size
    // before prepareAsync completes. AspectRatio(1.0) before init shrinks the
    // hole and leaves the Flutter loading spinner covering a blank plane.
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
