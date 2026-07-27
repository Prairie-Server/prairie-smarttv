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
  } = {},
): TvPlaybackCapabilities {
  const avplay = input.avplayAvailable ?? isAvPlayAvailable();
  const tizenMajor = tizenMajorVersion();

  const codecs_video = ["h264"];
  // HEVC Direct Play is reliable on modern Tizen with AVPlay.
  if (avplay || tizenMajor >= 3) {
    codecs_video.push("hevc");
  }

  const codecs_audio = probeSupportedAudioCodecs({
    systemInfo: input.systemInfo,
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
