import { isAvPlayAvailable } from "./avplay";
import { DEFAULT_TV_CAPABILITIES } from "../../player/types";

export interface TvPlaybackCapabilities {
  codecs_video: string[];
  codecs_audio: string[];
  containers: string[];
  max_resolution: string;
  hdr: boolean;
}

export interface SystemInfoApi {
  isSupportedAudioCodec?(codec: string): boolean;
  isSupportedVideoCodec?(codec: string): boolean;
}

/** Samsung systeminfo codec name → Prairie `codecs_audio` token. */
const AUDIO_CODEC_PROBES: ReadonlyArray<{ prairie: string; samsung: string }> = [
  { prairie: "aac", samsung: "AAC" },
  { prairie: "aac", samsung: "HE-AAC" },
  { prairie: "ac3", samsung: "AC3" },
  { prairie: "eac3", samsung: "E-AC3" },
  { prairie: "truehd", samsung: "TrueHD" },
  { prairie: "opus", samsung: "OPUS" },
  { prairie: "ac4", samsung: "AC4" },
  { prairie: "mp3", samsung: "MPEG" },
];

function tizenMajorVersion(): number {
  const ua = navigator.userAgent ?? "";
  const match = ua.match(/Tizen[/\s](\d+)/i);
  return match ? Number(match[1]) : 0;
}

/** Platform version including minor (Tizen 5.5 -> 5.5); 0 when not Tizen. */
export function tizenPlatformVersion(ua: string = navigator.userAgent ?? ""): number {
  const match = ua.match(/Tizen[/\s](\d+(?:\.\d+)?)/i);
  if (!match?.[1]) return 0;
  const version = Number(match[1]);
  return Number.isFinite(version) ? version : 0;
}

/** AV1 hardware decode starts with the 2020 panels (Tizen 5.5). */
const AV1_MIN_TIZEN_VERSION = 5.5;
/**
 * Samsung `isSupportedVideoCodec` tokens. Official docs list `AV1` /
 * `AV1_VR360` (SystemInfo since Tizen 6.0); `AV01` is kept for older OEM forks
 * that mirror the ISO fourcc.
 */
const AV1_PROBE_NAMES = ["AV1", "AV01", "AV1_VR360"];
const HEVC_PROBE_NAMES = ["HEVC", "H265", "H.265"];
const AV1_MEDIA_TYPE = 'video/mp4; codecs="av01.0.08M.08"';

function probeVideoCodec(systemInfo: SystemInfoApi | null, names: string[]): boolean | null {
  if (!systemInfo) return null;
  const rawProbe = Reflect.get(systemInfo, "isSupportedVideoCodec");
  if (typeof rawProbe !== "function") return null;
  const probe = rawProbe as (this: SystemInfoApi, name: string) => boolean;
  let sawAnswer = false;
  for (const name of names) {
    try {
      if (probe.call(systemInfo, name)) return true;
      sawAnswer = true;
    } catch {
      /* try the next spelling */
    }
  }
  // A definite "no" only counts when at least one probe answered.
  return sawAnswer ? false : null;
}

/** Secondary AV1 signal via HTMLMediaElement.canPlayType. */
export function canPlayAv1(): boolean {
  try {
    const video = document.createElement("video");
    return typeof video.canPlayType === "function" && video.canPlayType(AV1_MEDIA_TYPE) !== "";
  } catch {
    return false;
  }
}

/**
 * Whether this TV can Direct Play AV1.
 *
 * Combine signals with OR: a false `isSupportedVideoCodec` answer must not
 * veto a positive `canPlayType` on Tizen ≥ 5.5. 2022 QLEDs (Tizen 6.5) have
 * been seen to deny "AV1" in systeminfo while still decoding av01 in HTML5 /
 * AVPlay. Unknown / non-Tizen stays conservative (no advertise).
 */
export function probeAv1Support(
  input: {
    systemInfo?: SystemInfoApi | null;
    tizenVersion?: number;
    canPlayAv1?: boolean;
  } = {},
): boolean {
  const version = input.tizenVersion ?? tizenPlatformVersion();
  if (version > 0 && version < AV1_MIN_TIZEN_VERSION) return false;
  // Browser / unit hosts without a Tizen UA never advertise AV1.
  if (version === 0) return false;

  const systemInfo = input.systemInfo === undefined ? getSystemInfo() : input.systemInfo;
  const systeminfoOk = probeVideoCodec(systemInfo, AV1_PROBE_NAMES) === true;
  const mediaOk = (input.canPlayAv1 ?? canPlayAv1()) === true;
  return systeminfoOk || mediaOk;
}

/** Detail for on-device diagnostics — which AV1 signals fired. */
export function describeAv1Probe(
  input: {
    systemInfo?: SystemInfoApi | null;
    tizenVersion?: number;
    canPlayAv1?: boolean;
  } = {},
): {
  tizenVersion: number;
  systeminfo: boolean | null;
  canPlayType: boolean;
  supported: boolean;
} {
  const tizenVersion = input.tizenVersion ?? tizenPlatformVersion();
  const systemInfo = input.systemInfo === undefined ? getSystemInfo() : input.systemInfo;
  const systeminfo = probeVideoCodec(systemInfo, AV1_PROBE_NAMES);
  const canPlayType = input.canPlayAv1 ?? canPlayAv1();
  return {
    tizenVersion,
    systeminfo,
    canPlayType,
    supported: probeAv1Support({ systemInfo, tizenVersion, canPlayAv1: canPlayType }),
  };
}

function probeMaxResolution(): string {
  const width = Math.max(screen.width || 0, window.innerWidth || 0);
  const height = Math.max(screen.height || 0, window.innerHeight || 0);
  if (height >= 2160 || width >= 3840) return "2160p";
  if (height >= 1440 || width >= 2560) return "1440p";
  if (height >= 1080 || width >= 1920) return "1080p";
  return "720p";
}

function probeHdr(tizenMajor: number): boolean {
  try {
    if (
      typeof window.matchMedia === "function" &&
      window.matchMedia("(dynamic-range: high)").matches
    ) {
      return true;
    }
  } catch {
    /* ignore */
  }
  // HDR is common on Tizen 4+ panels; keep false on unknown/low versions.
  return tizenMajor >= 4;
}

function getSystemInfo(): SystemInfoApi | null {
  return window.webapis?.systeminfo ?? null;
}

/**
 * Probe which audio codecs this TV can Direct Play / remux-copy.
 * Prefer `webapis.systeminfo.isSupportedAudioCodec` (Tizen 6+); otherwise keep
 * the conservative DEFAULT_TV_CAPABILITIES list (no TrueHD/DTS/FLAC).
 */
export function probeSupportedAudioCodecs(
  input: {
    systemInfo?: SystemInfoApi | null;
    tizenMajor?: number;
  } = {},
): string[] {
  const systemInfo = input.systemInfo === undefined ? getSystemInfo() : input.systemInfo;
  const tizenMajor = input.tizenMajor ?? tizenMajorVersion();
  const base = [...DEFAULT_TV_CAPABILITIES.codecs_audio];

  if (systemInfo == null) {
    if (tizenMajor > 0 && tizenMajor < 4) return [...base, "dts"];
    return base;
  }

  const rawProbe = Reflect.get(systemInfo, "isSupportedAudioCodec");
  if (typeof rawProbe !== "function") {
    // Older Tizen sometimes Direct Plays DTS; modern firmwares usually do not.
    if (tizenMajor > 0 && tizenMajor < 4) {
      return [...base, "dts"];
    }
    return base;
  }
  const isSupportedAudioCodec = (codec: string): boolean =>
    Boolean((rawProbe as (this: SystemInfoApi, name: string) => boolean).call(systemInfo, codec));

  const supported = new Set<string>();
  for (const { prairie, samsung } of AUDIO_CODEC_PROBES) {
    try {
      if (isSupportedAudioCodec(samsung)) supported.add(prairie);
    } catch {
      /* ignore individual probe failures */
    }
  }

  // Always keep the baseline TV-safe set even if a probe falsely returns false.
  for (const codec of base) supported.add(codec);

  // DTS is not exposed via isSupportedAudioCodec; only advertise on old Tizen.
  if (tizenMajor > 0 && tizenMajor < 4) supported.add("dts");

  return [...supported];
}

/**
 * Probe what this TV can likely Direct Play. Falls back to DEFAULT_TV_CAPABILITIES
 * fields when the runtime cannot be inspected (unit tests / browser).
 */
export function probeTvPlaybackCapabilities(
  input: {
    avplayAvailable?: boolean;
    systemInfo?: SystemInfoApi | null;
    tizenVersion?: number;
    canPlayAv1?: boolean;
  } = {},
): TvPlaybackCapabilities {
  const avplay = input.avplayAvailable ?? isAvPlayAvailable();
  const tizenMajor = tizenMajorVersion();

  const systemInfo = input.systemInfo === undefined ? getSystemInfo() : input.systemInfo;
  const tizenVersion = input.tizenVersion ?? tizenPlatformVersion();

  const codecs_video = ["h264"];
  // Prefer the platform probe for HEVC; fall back to the version heuristic when
  // the firmware does not expose it (HEVC is reliable on modern Tizen + AVPlay).
  const hevcProbe = probeVideoCodec(systemInfo, HEVC_PROBE_NAMES);
  if (hevcProbe ?? (avplay || tizenMajor >= 3)) {
    codecs_video.push("hevc");
  }
  // AV1 has to be advertised for the server to remux instead of re-encoding it.
  if (
    probeAv1Support({
      systemInfo,
      tizenVersion,
      canPlayAv1: input.canPlayAv1,
    })
  ) {
    codecs_video.push("av1");
  }

  const codecs_audio = probeSupportedAudioCodecs({
    systemInfo,
    tizenMajor,
  });
  // Prefer progressive containers AVPlay handles well; keep mkv when native player exists.
  const containers = avplay ? ["mp4", "mpegts", "hls", "mkv"] : ["mp4", "mpegts", "hls"];

  return {
    codecs_video,
    codecs_audio,
    containers,
    max_resolution: probeMaxResolution(),
    hdr: probeHdr(tizenMajor),
  };
}

export interface Av1AdvertiseOverrides {
  /** Inject `av1` into codecs_video even when the probe said no. */
  forceAv1?: boolean;
  /** Strip `av1` even when the probe said yes. */
  disableAv1?: boolean;
}

/** Apply user overrides on top of a fresh capability probe. */
export function applyAv1AdvertiseOverrides(
  caps: TvPlaybackCapabilities,
  overrides: Av1AdvertiseOverrides = {},
): TvPlaybackCapabilities {
  let codecs = [...caps.codecs_video];
  if (overrides.disableAv1) {
    codecs = codecs.filter((codec) => codec !== "av1");
  } else if (overrides.forceAv1 && !codecs.includes("av1")) {
    codecs.push("av1");
  }
  return { ...caps, codecs_video: codecs };
}

/**
 * Probe the panel, then apply Advertise/Disable AV1 settings before the list
 * is sent to Prairie as `codecs_video`.
 */
export function resolveAdvertisedCapabilities(
  overrides: Av1AdvertiseOverrides = {},
  probeInput: Parameters<typeof probeTvPlaybackCapabilities>[0] = {},
): TvPlaybackCapabilities {
  return applyAv1AdvertiseOverrides(probeTvPlaybackCapabilities(probeInput), overrides);
}
