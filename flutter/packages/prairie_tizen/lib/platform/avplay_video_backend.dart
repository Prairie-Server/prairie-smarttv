import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:video_player_avplay/video_player.dart';

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

  @override
  Future<void> load(String url, {Duration? startPosition}) async {
    final controller = VideoPlayerController.network(url);
    _controller = controller;
    controller.addListener(_onControllerUpdate);
    await controller.initialize();
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
      // Some streams have no embedded text tracks at all — an empty list
      // is the correct outcome, not an error worth surfacing.
      _subtitleTracks = [];
    }
    // AVPlay has no position-changed event in this plugin's public API, so
    // progress reporting (used for Prairie server watch-progress sync) is
    // polled — same 1s cadence the TS player used for its progress timer.
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
  List<SubtitleTrackChoice> get subtitleTracks => _subtitleTracks;

  @override
  Future<void> selectSubtitleTrack(int? trackId) async {
    final controller = _controller;
    if (controller == null || trackId == null) return;
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
  Duration? get duration => _controller?.value.duration.end;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  Widget buildSurface() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller));
  }

  @override
  Future<void> dispose() async {
    _positionTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    await _positionController.close();
    await _captionController.close();
    await _controller?.dispose();
    _controller = null;
  }
}
