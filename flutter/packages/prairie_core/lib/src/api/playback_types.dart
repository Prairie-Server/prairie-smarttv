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

/// Mirrors `BuildPlaybackStartInput` from src/api/playback.ts.
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
}

/// Mirrors `buildPlaybackStartRequest`: builds the POST /api/v1/playback/start
/// body, omitting `play_method` when unset so Prairie can prefer remux/auto.
Map<String, dynamic> buildPlaybackStartRequest(BuildPlaybackStartInput input) {
  final body = <String, dynamic>{
    'file_id': input.fileId,
    'profile_id': input.profileId,
    'codecs_video': input.codecsVideo ?? TvCapabilities.codecsVideo,
    'codecs_audio': input.codecsAudio ?? TvCapabilities.codecsAudio,
    'containers': input.containers ?? TvCapabilities.containers,
    'max_resolution': input.maxResolution ?? TvCapabilities.maxResolution,
    'hdr': input.hdr ?? TvCapabilities.hdr,
    'max_audio_channels': input.maxAudioChannels ?? TvCapabilities.maxAudioChannels,
    'supports_bitmap_subtitle_burn_in': false,
  };

  if (input.forcedPlayMethod != null) {
    body['play_method'] = input.forcedPlayMethod!.wireValue;
  }
  if (input.startPosition != null && input.startPosition! > 0) {
    body['start_position'] = input.startPosition;
  }

  return body;
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
