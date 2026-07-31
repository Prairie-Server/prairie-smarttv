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
    this.maxAudioChannels = 6,
    this.supportsHlsTranscode = true,
  });

  final List<String> codecsVideo;
  final List<String> codecsAudio;
  final List<String> containers;
  final String maxResolution;
  final bool hdr;
  /// Caps transcode-audio channel layout. `6` (5.1) is Samsung's documented
  /// ceiling for non-8K TVs — Moonfin's own reference client caps identically
  /// (`caps.uhd8K ? 8 : 6`); 7.1/8-channel is only documented on the 8K tier.
  /// We have no 8K-panel detection yet (see [buildTizenCapabilities]), so
  /// this is always `6` until that's wired up.
  final int maxAudioChannels;
  /// Whether the active video backend can play an HLS stream at all —
  /// distinct from [codecsVideo]/[containers] (which describe the *source*
  /// codec/container, not the transport used to deliver a genuine re-encode).
  /// `false` on Tizen's `video_player_videohole`: confirmed on-device that
  /// its native `player_set_uri` + `player_prepare_async` call has no
  /// HLS-specific setup at all (no streaming-type/format hint is ever read —
  /// `formatHint` is parsed into the plugin's native message struct but never
  /// consumed) and fails every attempt with `PLAYER_ERROR_NOT_SUPPORTED_FORMAT`
  /// ("Not supported format"), master-playlist-resolution and format-hint
  /// bugs notwithstanding — this is a basic `player.h` capability gap, not a
  /// client bug. Real HLS/DASH needs the PlusPlayer/ESPlusPlayer pipeline,
  /// which this app deliberately avoids (its GStreamer HLS demux hard-links
  /// `libclearkey.so.0`, blocked by Smack on a retail cert — the reason this
  /// backend was chosen over AVPlay in the first place). Any quality-menu
  /// option that requires an actual re-encode (anything but `original`) goes
  /// through `/playback/transcode/start`'s HLS transport, so the quality
  /// picker must not offer those options when this is `false` — see
  /// `_qualityOptions` in `player_screen.dart`.
  final bool supportsHlsTranscode;

  /// Conservative defaults used when no platform probe has run yet (unknown
  /// platform, or webOS — see [buildWebosCapabilities], which has no
  /// Moonfin-equivalent research behind it yet). Matches
  /// `DEFAULT_TV_CAPABILITIES` — note: does **not** include `av1`.
  ///
  /// `codecsAudio` is just `aac` here specifically because we don't know the
  /// platform. Tizen has its own audio codec table — see
  /// [probeAudioCodecSupport] — used by [buildTizenCapabilities] instead of
  /// this fallback.
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
    int? maxAudioChannels,
    bool? supportsHlsTranscode,
  }) =>
      TvPlaybackCapabilities(
        codecsVideo: codecsVideo ?? this.codecsVideo,
        codecsAudio: codecsAudio ?? this.codecsAudio,
        containers: containers ?? this.containers,
        maxResolution: maxResolution ?? this.maxResolution,
        hdr: hdr ?? this.hdr,
        maxAudioChannels: maxAudioChannels ?? this.maxAudioChannels,
        supportsHlsTranscode: supportsHlsTranscode ?? this.supportsHlsTranscode,
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

/// Matches the Jellyfin Tizen client Moonfin's shipped codec mapping
/// (`platform-tizen/src/deviceProfile.js`, `testAc3Support`/`testEac3Support`/
/// `testDtsSupport`), which in turn matches Samsung's published per-year TV
/// media specs (developer.samsung.com/smarttv/develop/specifications/
/// media-specifications/20XX-tv-video-specifications.html — checked 2021
/// through 2025 directly): AC3 and EAC3/DD+ are listed as supported,
/// unconditionally, every year, with no Tizen-version gate and no
/// container-specific carve-out — Moonfin puts both straight into its
/// general MP4/MKV/TS/MOV/AVI direct-play audio codec list. DTS is the one
/// codec every year's page explicitly excludes ("The DTS Audio codec is not
/// supported on 20XX TVs"), matching `testDtsSupport() => false`.
///
/// TrueHD is left out: Moonfin only advertises it behind an explicit
/// "experimental" settings toggle plus a live `webapis.systeminfo
/// .isSupportedAudioCodec('TrueHD')` query — a Tizen **Web** API (WebKit/JS
/// runtime only), unreachable from this native Flutter/Tizen app without a
/// WebView bridge. That bridge is deliberately not built here; revisit
/// TrueHD once/if it is.
List<String> probeAudioCodecSupport({required double tizenVersion}) {
  return const ['aac', 'ac3', 'eac3'];
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

/// Apply the user's manual 8K-panel override (`PlaybackSettings.is8KPanel`)
/// to the base capabilities' audio channel cap — see [buildTizenCapabilities]
/// `uhd8K` doc for why this can't be auto-detected instead.
TvPlaybackCapabilities applyAudioChannelOverride(TvPlaybackCapabilities caps, {bool is8KPanel = false}) =>
    is8KPanel ? caps.copyWith(maxAudioChannels: 8) : caps;

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
///
/// [uhd8K] has no auto-detection at all, and unlike [uhd] there's no
/// screen-size heuristic to fall back on either: Samsung TV apps render at a
/// fixed 1080p reference surface that the platform then upscales to the
/// physical panel, so every size signal available to app code — Flutter's
/// `PlatformDispatcher.displays` and `device_info_plus_tizen`'s
/// `screenWidth`/`screenHeight` (itself backed by the native
/// `http://tizen.org/feature/screen.width`/`.height` keys) — reports that
/// same fixed 1920×1080 regardless of whether the physical panel is 1080p,
/// 4K, or 8K. Confirmed empirically on a real 8K Neo QLED unit: both APIs
/// came back 1920×1080-derived. [uhd8K] is therefore a manual signal from
/// `PlaybackSettings.is8KPanel` — there is no better answer available from
/// application code on this platform. Defaults to `false`.
TvPlaybackCapabilities buildTizenCapabilities({
  required double tizenVersion,
  required int screenWidth,
  required int screenHeight,
  bool avplayAvailable = true,
  bool? systemInfoAv1,
  bool? uhd,
  bool uhd8K = false,
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
    // Samsung's 8K-tier spec documents 7.1/8-channel audio; the general
    // (4K Premium/Standard/Basic) tier docs cap at 5.1/6, per Moonfin's
    // identical uhd8K ? 8 : 6 split.
    maxAudioChannels: uhd8K ? 8 : 6,
    // See TvPlaybackCapabilities.supportsHlsTranscode doc — confirmed
    // on-device that video_player_videohole cannot play HLS at all.
    supportsHlsTranscode: false,
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
