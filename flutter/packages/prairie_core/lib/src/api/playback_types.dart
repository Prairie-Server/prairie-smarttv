import 'dart:math';

/// Mirrors `PlayMethod`/`ForcedPlayMethod` from src/platform/types.ts.
enum PlayMethod { direct, remux, transcode }

extension PlayMethodJson on PlayMethod {
  String get wireValue => name;
}

/// Conservative TV capability advertisement for foundation playback. Mirrors
/// `DEFAULT_TV_CAPABILITIES` from src/player/types.ts.
class TvCapabilities {
  static const codecsVideo = ['h264', 'hevc'];
  static const codecsAudio = ['aac', 'ac3', 'eac3', 'mp3'];
  static const containers = ['mp4', 'mpegts', 'hls', 'mkv'];
  static const maxResolution = '2160p';
  static const hdr = true;
  static const maxAudioChannels = 6;
}

/// Mirrors the playback-v3 start contract used by both the native /api/v2
/// endpoint and the frozen /api/v1 bridge. The bridge now rejects pre-v3
/// request bodies, so this client must speak protocol v3 even while keeping
/// the legacy lifecycle endpoints for compatibility.

class BuildPlaybackStartInput {
  const BuildPlaybackStartInput({
    required this.fileId,
    required this.profileId,
    this.forcedPlayMethod,
    this.startPosition,
    this.codecsVideo,
    this.codecsAudio,
    this.containers,
    this.maxResolution,
    this.hdr,
    this.maxAudioChannels,
    this.playbackAttemptId,
  });

  final int fileId;
  final String profileId;
  final PlayMethod? forcedPlayMethod;
  final double? startPosition;
  final List<String>? codecsVideo;
  final List<String>? codecsAudio;
  final List<String>? containers;
  final String? maxResolution;
  final bool? hdr;
  final int? maxAudioChannels;

  /// Stable identity for retrying one playback start. Generated when omitted.
  final String? playbackAttemptId;
}

String _newPlaybackAttemptId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}


/// Mirrors `buildPlaybackStartRequest`: builds the POST /api/v1/playback/start
/// body, omitting `play_method` when unset so Prairie can prefer remux/auto.
Map<String, dynamic> buildPlaybackStartRequest(BuildPlaybackStartInput input) {
  final videoCodecs = input.codecsVideo ?? TvCapabilities.codecsVideo;
  final audioCodecs = input.codecsAudio ?? TvCapabilities.codecsAudio;
  final containers = input.containers ?? TvCapabilities.containers;
  final maxResolution = input.maxResolution ?? TvCapabilities.maxResolution;
  final hdr = input.hdr ?? TvCapabilities.hdr;
  final maxAudioChannels = input.maxAudioChannels ?? TvCapabilities.maxAudioChannels;

  // The v3 planner selects the route from the delivery classes the client
  // advertises. Restricting the classes is the protocol-v3 equivalent of the
  // old forceDirectPlay / forceTranscode switches.
  final deliveries = <String, dynamic>{
    'original_http': {
      'enabled': input.forcedPlayMethod != PlayMethod.transcode,
      'supported_on_device': true,
      'containers': containers,
      'video_codecs': videoCodecs,
      'audio_decode_codecs': audioCodecs,
      'audio_passthrough_codecs': const <String>[],
      'max_channels': maxAudioChannels,
      'subtitles': {
        'embedded_text': false,
        'sidecar_text': false,
        'ass_styling': false,
        'embedded_bitmap': false,
        'sidecar_bitmap': false,
        'font_attachments': false,
      },
      'features': const <String>[],
      'auth_header_refresh': false,
      'validated_claims': const <String>[],
      'transformations': const <String>[],
    },
    'progressive': {
      'enabled': input.forcedPlayMethod != PlayMethod.transcode,
      'supported_on_device': true,
      'containers': containers,
      'video_codecs': videoCodecs,
      'audio_decode_codecs': audioCodecs,
      'audio_passthrough_codecs': const <String>[],
      'max_channels': maxAudioChannels,
      'subtitles': {
        'embedded_text': false,
        'sidecar_text': false,
        'ass_styling': false,
        'embedded_bitmap': false,
        'sidecar_bitmap': false,
        'font_attachments': false,
      },
      'features': const <String>[],
      'auth_header_refresh': false,
      'validated_claims': const <String>[],
      'transformations': const <String>[],
    },
    'hls': {
      'enabled': input.forcedPlayMethod != PlayMethod.direct,
      'supported_on_device': true,
      'containers': const <String>['hls'],
      'video_codecs': videoCodecs,
      'audio_decode_codecs': audioCodecs,
      'audio_passthrough_codecs': const <String>[],
      'max_channels': maxAudioChannels,
      'subtitles': {
        'embedded_text': false,
        'sidecar_text': false,
        'ass_styling': false,
        'embedded_bitmap': false,
        'sidecar_bitmap': false,
        'font_attachments': false,
      },
      'features': const <String>[],
      'auth_header_refresh': false,
      'validated_claims': const <String>[],
      'transformations': const <String>[],
    },
  };

  return {
    'protocol_version': 3,
    'client_features': const [
      'playback_plan_v3',
      'neutral_playback_v3_contract_v1',
      'embedded_subtitles_v1',
    ],
    'file_id': input.fileId,
    'profile_id': input.profileId,
    'playback_attempt_id': input.playbackAttemptId ?? _newPlaybackAttemptId(),
    'quality_preference': input.forcedPlayMethod == PlayMethod.direct ? 'original' : 'auto',
    'subtitle_fidelity_preference': 'compatible',
    if (input.startPosition != null && input.startPosition! > 0) 'start_position': input.startPosition,
    'progress_persistence': 'server',
    'metered': false,
    'client_capabilities': {
      'video_evidence': 'declared',
      'audio_evidence': 'declared',
      'codecs_video': videoCodecs,
      'codecs_video_hardware': videoCodecs,
      'codecs_audio': audioCodecs,
      'containers': containers,
      'max_resolution': maxResolution,
      'hdr': hdr,
      'hdr_details': {
        'hdr10': hdr,
        'hdr10_plus': false,
        'hlg': false,
        'dolby_vision_profiles': const <int>[],
      },
    },
    'client_playback_context': {
      'protocol_version': 3,
      'form_factor': 'tv',
      'app_version': '1.0.0',
      'app_channel': 'release',
      'device': {
        'platform': 'smarttv',
      },
      'output': {
        'hdr_details': {
          'hdr10': hdr,
          'hdr10_plus': false,
          'hlg': false,
          'dolby_vision_profiles': const <int>[],
        },
        'sink_type': 'display',
      },
      'deliveries': deliveries,
    },
  };
}

/// Mirrors `withPlayMethod`.
Map<String, dynamic> withPlayMethod(Map<String, dynamic> body, PlayMethod? method) {
  final next = Map<String, dynamic>.from(body);
  if (method == null) {
    next.remove('play_method');
  } else {
    next['play_method'] = method.wireValue;
  }
  return next;
}
