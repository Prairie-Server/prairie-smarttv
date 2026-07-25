import type { PlatformKind, PlayerBackendPreference, ResolvedPlayerBackend } from "../platform/types";
import { isAvPlayAvailable } from "../platform/tizen/avplay";
import { isStarfishEnvironment } from "../platform/webos/starfish";

export interface PlayerSelectionInput {
  preference: PlayerBackendPreference;
  platform: PlatformKind;
  /** Override availability in tests. */
  avplayAvailable?: boolean;
  starfishAvailable?: boolean;
}

/**
 * Choose the concrete player backend for this device + user preference.
 * Auto → native on TV platforms, HTML5 in browser / as fallback.
 */
export function selectPlayerBackend(input: PlayerSelectionInput): ResolvedPlayerBackend {
  const avplayAvailable = input.avplayAvailable ?? isAvPlayAvailable();
  const starfishAvailable = input.starfishAvailable ?? isStarfishEnvironment();

  if (input.preference === "html5") {
    return "html5";
  }

  if (input.preference === "native") {
    if (input.platform === "tizen" && avplayAvailable) return "avplay";
    if (input.platform === "webos") return "starfish";
    // Native requested but unavailable — degrade gracefully.
    if (avplayAvailable) return "avplay";
    if (starfishAvailable) return "starfish";
    return "html5";
  }

  // auto
  if (input.platform === "tizen" && avplayAvailable) return "avplay";
  if (input.platform === "webos") return "starfish";
  return "html5";
}
