/// Probed / advertised TV playback capabilities sent to Prairie as
/// `codecs_video` / `codecs_audio` / etc. on `/playback/start`.
///
/// Mirrors `TvPlaybackCapabilities` from
/// `src/platform/tizen/deviceCapabilities.ts`.
class TvPlaybackCapabilities {
  const TvPlaybackCapabilities({
    required this.codecsVideo,
    required this.codecsAudio,
    required this.containers,
    required this.maxResolution,
    required this.hdr,
  });

  final List<String> codecsVideo;
  final List<String> codecsAudio;
  final List<String> containers;
  final String maxResolution;
  final bool hdr;

  /// Conservative defaults used when no platform probe has run yet.
  /// Matches `DEFAULT_TV_CAPABILITIES` — note: does **not** include `av1`.
  ///
  /// `codecsAudio` is deliberately just `aac`: there is no audio-codec probe
  /// (unlike [probeAv1Support] for video), and `codecsAudio`/`containers` are
  /// advertised as independent lists with no way to say "ac3 works in ts but
  /// not mp4." AC3/EAC3/MP3 support varies by container in practice on this
  /// platform, so claiming them at all risks a codec the server picks for a
  /// container this player can't decode it in (e.g. AC3-in-MP4) — cheaper to
  /// eat an always-safe AAC re-encode than guess wrong on an unprobed codec.
  static const defaults = TvPlaybackCapabilities(
    codecsVideo: ['h264', 'hevc'],
    codecsAudio: ['aac'],
    containers: ['mp4', 'mpegts', 'hls', 'mkv'],
    maxResolution: '2160p',
    hdr: true,
  );

  TvPlaybackCapabilities copyWith({
    List<String>? codecsVideo,
    List<String>? codecsAudio,
    List<String>? containers,
    String? maxResolution,
    bool? hdr,
  }) =>
      TvPlaybackCapabilities(
        codecsVideo: codecsVideo ?? this.codecsVideo,
        codecsAudio: codecsAudio ?? this.codecsAudio,
        containers: containers ?? this.containers,
        maxResolution: maxResolution ?? this.maxResolution,
        hdr: hdr ?? this.hdr,
      );
}

/// AV1 hardware decode starts with the 2020 panels (Tizen 5.5).
const av1MinTizenVersion = 5.5;

/// Whether this TV can Direct Play AV1.
///
/// Combine signals with OR: a false systeminfo answer must not veto a positive
/// media/capability signal on Tizen ≥ 5.5. Unknown / non-Tizen stays
/// conservative (no advertise). Mirrors `probeAv1Support`.
bool probeAv1Support({
  required double tizenVersion,
  bool systemInfoAv1 = false,
  bool canPlayAv1 = false,
}) {
  if (tizenVersion > 0 && tizenVersion < av1MinTizenVersion) return false;
  // Browser / unit hosts without a Tizen version never advertise AV1.
  if (tizenVersion == 0) return false;
  return systemInfoAv1 || canPlayAv1;
}

/// AC3/EAC3 supported above this Tizen version. Deliberately **above** 6.5,
/// not at/below it: a real AC3-in-MP4 remux failed on a QN700B — a confirmed
/// 2022 model, Tizen 6.5 — with "unsupported audio codec," despite Samsung's
/// general 2025 TV spec page documenting AC-3 as supported "regardless of
/// container type, including MP4." That contradiction means the published
/// spec isn't sufficient proof for this codec on its own — this threshold is
/// a conservative placeholder that excludes the one model-year with a
/// confirmed failure (2022 / Tizen 6.5), not a verified-safe floor for 2023
/// (Tizen 7.0) onward. Tighten or loosen only against a real per-version
/// field report, same discipline as [av1MinTizenVersion].
const ac3MinTizenVersion = 7.0;

/// Audio codec support, by Tizen version — mirrors [probeAv1Support]'s shape
/// (a documented-support floor) rather than a live query: `webapis.systeminfo
/// .isSupportedAudioCodec` is a real per-device Samsung API, but it's a Tizen
/// **Web** API (WebKit/JS runtime only) — unreachable from a native
/// Flutter/Tizen app without a WebView bridge, which is its own project (not
/// built here). `aac` never varies; it's the one codec with no observed
/// container-dependent failure. DTS is never included: Samsung's own 2025 and
/// 2026 TV spec pages state plainly, identically, "The DTS Audio codec is not
/// supported on 20XX TVs." MP3 is left out too — same container-dependent risk
/// profile as AC3, with no field data either way yet.
List<String> probeAudioCodecSupport({required double tizenVersion}) {
  final codecs = <String>['aac'];
  if (tizenVersion >= ac3MinTizenVersion) {
    codecs.addAll(['ac3', 'eac3']);
  }
  return codecs;
}

/// Apply user Advertise/Disable AV1 overrides on top of a probe result.
TvPlaybackCapabilities applyAv1AdvertiseOverrides(
  TvPlaybackCapabilities caps, {
  bool forceAv1 = false,
  bool disableAv1 = false,
}) {
  var codecs = List<String>.from(caps.codecsVideo);
  if (disableAv1) {
    codecs = codecs.where((c) => c != 'av1').toList();
  } else if (forceAv1 && !codecs.contains('av1')) {
    codecs.add('av1');
  }
  return caps.copyWith(codecsVideo: codecs);
}

/// Build capabilities from a known Tizen platform version + panel size.
///
/// Native Flutter has no HTML5 `canPlayType` / `webapis.systeminfo` bridge, so
/// AV1 is advertised from the hardware floor (Tizen ≥ 5.5) whenever the
/// native AVPlay backend is in use — matching panels that decode av01 even
/// when OEM systeminfo lies (see TS QLED 6.5 note).
///
/// [uhd] mirrors webOS / TS ProductInfo (`isUdPanelSupported`): Tizen Flutter
/// surfaces usually report 1920×1080 even on UHD panels, which previously
/// forced 1080p HEVC encodes of native 4K. When [uhd] is null and AVPlay is
/// available on Tizen ≥ 5.0, we assume UHD (same class of panels that ship
/// with AVPlay apps).
TvPlaybackCapabilities buildTizenCapabilities({
  required double tizenVersion,
  required int screenWidth,
  required int screenHeight,
  bool avplayAvailable = true,
  bool? systemInfoAv1,
  bool? uhd,
}) {
  final codecsVideo = <String>['h264'];
  final major = tizenVersion.floor();
  if (avplayAvailable || major >= 3) {
    codecsVideo.add('hevc');
  }
  // Native AVPlay path: treat Tizen ≥ 5.5 as canPlayAv1=true (no HTML5 probe).
  final av1 = probeAv1Support(
    tizenVersion: tizenVersion,
    systemInfoAv1: systemInfoAv1 ?? false,
    canPlayAv1: avplayAvailable && tizenVersion >= av1MinTizenVersion,
  );
  if (av1) codecsVideo.add('av1');

  final containers = avplayAvailable
      ? <String>['mp4', 'mpegts', 'hls', 'mkv']
      : <String>['mp4', 'mpegts', 'hls'];

  var maxRes = resolutionTokenFromSize(screenWidth, screenHeight);
  final treatAsUhd = uhd ?? (avplayAvailable && tizenVersion >= 5.0);
  if (treatAsUhd && maxRes != '2160p') {
    maxRes = '2160p';
  }

  return TvPlaybackCapabilities(
    codecsVideo: codecsVideo,
    codecsAudio: probeAudioCodecSupport(tizenVersion: tizenVersion),
    containers: containers,
    maxResolution: maxRes,
    hdr: major >= 4,
  );
}

/// webOS AV1 hardware decode is common from ~2020 panels (webOS 5+); we
/// advertise from webOS ≥ 6 to stay conservative without a canPlayType probe.
const av1MinWebosVersion = 6.0;

/// Build capabilities from a known webOS platform version + panel size.
///
/// Uses `device_info_plus_webos` signals (version, screen size, HDR10/UHD
/// flags) plus the native `video_player_drm` backend availability.
TvPlaybackCapabilities buildWebosCapabilities({
  required double webosVersion,
  required int screenWidth,
  required int screenHeight,
  bool nativePlayerAvailable = true,
  bool? hdr10,
  bool? uhd,
}) {
  final codecsVideo = <String>['h264'];
  final major = webosVersion.floor();
  if (nativePlayerAvailable || major >= 3) {
    codecsVideo.add('hevc');
  }
  if (nativePlayerAvailable && webosVersion >= av1MinWebosVersion) {
    codecsVideo.add('av1');
  }

  final containers = nativePlayerAvailable
      ? <String>['mp4', 'mpegts', 'hls', 'mkv']
      : <String>['mp4', 'mpegts', 'hls'];

  var maxRes = resolutionTokenFromSize(screenWidth, screenHeight);
  if (uhd == true && maxRes != '2160p') {
    maxRes = '2160p';
  }

  return TvPlaybackCapabilities(
    codecsVideo: codecsVideo,
    codecsAudio: List<String>.from(TvPlaybackCapabilities.defaults.codecsAudio),
    containers: containers,
    maxResolution: maxRes,
    hdr: hdr10 ?? major >= 4,
  );
}

/// Map panel pixels to a Prairie `max_resolution` token.
String resolutionTokenFromSize(int width, int height) {
  final w = width < 0 ? 0 : width;
  final h = height < 0 ? 0 : height;
  if (h >= 2160 || w >= 3840) return '2160p';
  if (h >= 1440 || w >= 2560) return '1440p';
  if (h >= 1080 || w >= 1920) return '1080p';
  if (h > 0 || w > 0) return '720p';
  return '720p';
}

/// AVPlay `ADAPTIVE_INFO` FIXED_MAX_RESOLUTION value for a Prairie token.
String avPlayFixedMaxResolution(String? token) {
  switch ((token ?? '').trim().toLowerCase()) {
    case '2160p':
    case '4k':
    case 'uhd':
      return '3840x2160';
    case '1440p':
      return '2560x1440';
    case '720p':
      return '1280x720';
    case '1080p':
    default:
      return '1920x1080';
  }
}
