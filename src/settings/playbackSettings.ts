import type { ForcedPlayMethod, PlayerBackendPreference, PlayMethod } from "../platform/types";

export const PLAYBACK_SETTINGS_KEY = "prairie.playbackSettings";

export interface PlaybackSettings {
  /** Auto picks native on Tizen/webOS, HTML5 elsewhere. */
  playerBackend: PlayerBackendPreference;
  /** Send play_method: "direct" to Prairie. */
  forceDirectPlay: boolean;
  /** Send play_method: "transcode" to Prairie. */
  forceTranscode: boolean;
}

export const DEFAULT_PLAYBACK_SETTINGS: PlaybackSettings = {
  playerBackend: "auto",
  forceDirectPlay: false,
  forceTranscode: false,
};

function isPlayerBackend(value: unknown): value is PlayerBackendPreference {
  return value === "auto" || value === "html5" || value === "native";
}

export function normalizePlaybackSettings(
  input: Partial<PlaybackSettings> | null | undefined,
): PlaybackSettings {
  const next: PlaybackSettings = {
    ...DEFAULT_PLAYBACK_SETTINGS,
    ...(input ?? {}),
  };

  if (!isPlayerBackend(next.playerBackend)) {
    next.playerBackend = DEFAULT_PLAYBACK_SETTINGS.playerBackend;
  }

  next.forceDirectPlay = Boolean(next.forceDirectPlay);
  next.forceTranscode = Boolean(next.forceTranscode);

  // Direct wins when both are somehow set (UI should prevent this).
  if (next.forceDirectPlay && next.forceTranscode) {
    next.forceTranscode = false;
  }

  return next;
}

export function loadPlaybackSettings(
  storage: Pick<Storage, "getItem"> = localStorage,
): PlaybackSettings {
  try {
    const raw = storage.getItem(PLAYBACK_SETTINGS_KEY);
    if (!raw) return { ...DEFAULT_PLAYBACK_SETTINGS };
    return normalizePlaybackSettings(JSON.parse(raw) as Partial<PlaybackSettings>);
  } catch {
    return { ...DEFAULT_PLAYBACK_SETTINGS };
  }
}

export function savePlaybackSettings(
  settings: PlaybackSettings,
  storage: Pick<Storage, "setItem"> = localStorage,
): PlaybackSettings {
  const normalized = normalizePlaybackSettings(settings);
  storage.setItem(PLAYBACK_SETTINGS_KEY, JSON.stringify(normalized));
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
