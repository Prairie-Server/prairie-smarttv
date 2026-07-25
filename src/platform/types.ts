export type PlatformKind = "browser" | "tizen" | "webos";

export type PlayerBackendPreference = "auto" | "html5" | "native";

export type ResolvedPlayerBackend = "html5" | "avplay" | "starfish";

export type PlayMethod = "direct" | "remux" | "transcode";

export type ForcedPlayMethod = PlayMethod | null;
