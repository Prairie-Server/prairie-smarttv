import type { ForcedPlayMethod, PlayerBackendPreference, PlayMethod } from "../platform/types";
import { PLAYBACK_SETTINGS_KEY } from "../storage/persist";
import { scheduleDurablePersist } from "../storage/durableStorage";
import {
  DEFAULT_SUBTITLE_APPEARANCE,
  normalizeSubtitleAppearance,
  type SubtitleAppearance,
} from "./subtitleAppearance";

export { PLAYBACK_SETTINGS_KEY };

export interface PlaybackSettings {
  /** Auto picks native on Tizen/webOS, HTML5 elsewhere. */
  playerBackend: PlayerBackendPreference;
  /** Send play_method: "direct" to Prairie. */
  forceDirectPlay: boolean;
  /** Send play_method: "transcode" to Prairie. */
  forceTranscode: boolean;
  /**
   * Advertise `av1` in codecs_video even when the capability probe said no —
   * escape hatch for panels (e.g. some 2022 QLEDs) that misreport support.
   */
  forceAv1: boolean;
  /** Strip `av1` from codecs_video even when the probe said yes. */
  disableAv1: boolean;
  /** On-screen subtitle look (text / background). */
  subtitleAppearance: SubtitleAppearance;
  /** Preferred subtitle language code when available (e.g. "eng"). Empty = Off preference. */
  preferredSubtitleLanguage: string;
}

export const DEFAULT_PLAYBACK_SETTINGS: PlaybackSettings = {
  playerBackend: "auto",
  forceDirectPlay: false,
  forceTranscode: false,
  forceAv1: false,
  disableAv1: false,
  subtitleAppearance: { ...DEFAULT_SUBTITLE_APPEARANCE },
  preferredSubtitleLanguage: "",
};

function isPlayerBackend(value: unknown): value is PlayerBackendPreference {
  return value === "auto" || value === "html5" || value === "native";
}

export function normalizePlaybackSettings(
  input: Partial<PlaybackSettings> | null | undefined,
): PlaybackSettings {
  const next: PlaybackSettings = {
    ...DEFAULT_PLAYBACK_SETTINGS,
    ...input,
    subtitleAppearance: normalizeSubtitleAppearance(input?.subtitleAppearance),
  };

  if (!isPlayerBackend(next.playerBackend)) {
    next.playerBackend = DEFAULT_PLAYBACK_SETTINGS.playerBackend;
  }

  next.forceDirectPlay = next.forceDirectPlay === true;
  next.forceTranscode = next.forceTranscode === true;
  next.forceAv1 = next.forceAv1 === true;
  next.disableAv1 = next.disableAv1 === true;
  next.preferredSubtitleLanguage =
    typeof next.preferredSubtitleLanguage === "string"
      ? next.preferredSubtitleLanguage.trim().toLowerCase()
      : "";

  // Direct wins when both are somehow set (UI should prevent this).
  if (next.forceDirectPlay && next.forceTranscode) {
    next.forceTranscode = false;
  }
  // Disable wins over force — safer default if both are somehow set.
  if (next.forceAv1 && next.disableAv1) {
    next.forceAv1 = false;
  }

  return next;
}

export function loadPlaybackSettings(
  storage: Pick<Storage, "getItem"> = localStorage,
): PlaybackSettings {
  try {
    const raw = storage.getItem(PLAYBACK_SETTINGS_KEY);
    if (!raw)
      return {
        ...DEFAULT_PLAYBACK_SETTINGS,
        subtitleAppearance: { ...DEFAULT_SUBTITLE_APPEARANCE },
      };
    return normalizePlaybackSettings(JSON.parse(raw) as Partial<PlaybackSettings>);
  } catch {
    return { ...DEFAULT_PLAYBACK_SETTINGS, subtitleAppearance: { ...DEFAULT_SUBTITLE_APPEARANCE } };
  }
}

export function savePlaybackSettings(
  settings: PlaybackSettings,
  storage: Pick<Storage, "setItem"> = localStorage,
): PlaybackSettings {
  const normalized = normalizePlaybackSettings(settings);
  storage.setItem(PLAYBACK_SETTINGS_KEY, JSON.stringify(normalized));
  scheduleDurablePersist();
  return normalized;
}

/**
 * Resolve the play_method sent to POST /api/v1/playback/start.
 * - Forced direct / transcode when troubleshooting toggles are on
 * - Otherwise omit (null) so Prairie can prefer remux / auto
 */
export function resolveForcedPlayMethod(settings: PlaybackSettings): ForcedPlayMethod {
  if (settings.forceDirectPlay) return "direct";
  if (settings.forceTranscode) return "transcode";
  return null;
}

export function describePlayMethodPreference(settings: PlaybackSettings): PlayMethod | "auto" {
  return resolveForcedPlayMethod(settings) ?? "auto";
}

/** Pick a subtitle index from session tracks using language preference. -1 = Off. */
export function resolvePreferredSubtitleIndex(
  tracks: Array<{ language?: string; index?: number }>,
  preferredLanguage: string,
): number {
  const pref = preferredLanguage.trim().toLowerCase();
  if (!pref || !tracks.length) return -1;
  const exact = tracks.findIndex((t) => (t.language ?? "").toLowerCase() === pref);
  if (exact >= 0) return exact;
  const prefix = tracks.findIndex((t) => (t.language ?? "").toLowerCase().startsWith(pref));
  return prefix;
}
