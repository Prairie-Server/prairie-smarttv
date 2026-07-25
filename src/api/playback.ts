import type { ForcedPlayMethod, PlayMethod } from "../platform/types";
import { DEFAULT_TV_CAPABILITIES, type PlaybackStartRequest } from "../player/types";

export interface BuildPlaybackStartInput {
  fileId: number;
  profileId: string;
  forcedPlayMethod?: ForcedPlayMethod;
  startPosition?: number;
  codecsVideo?: string[];
  codecsAudio?: string[];
  containers?: string[];
  maxResolution?: string;
  hdr?: boolean;
}

/**
 * Build POST /api/v1/playback/start body.
 * Omits play_method when unset so Prairie can prefer remux / auto.
 */
export function buildPlaybackStartRequest(input: BuildPlaybackStartInput): PlaybackStartRequest {
  const body: PlaybackStartRequest = {
    file_id: input.fileId,
    profile_id: input.profileId,
    codecs_video: input.codecsVideo ?? [...DEFAULT_TV_CAPABILITIES.codecs_video],
    codecs_audio: input.codecsAudio ?? [...DEFAULT_TV_CAPABILITIES.codecs_audio],
    containers: input.containers ?? [...DEFAULT_TV_CAPABILITIES.containers],
    max_resolution: input.maxResolution ?? DEFAULT_TV_CAPABILITIES.max_resolution,
    hdr: input.hdr ?? DEFAULT_TV_CAPABILITIES.hdr,
    supports_bitmap_subtitle_burn_in: false,
  };

  if (input.forcedPlayMethod) {
    body.play_method = input.forcedPlayMethod;
  }

  if (input.startPosition != null && input.startPosition > 0) {
    body.start_position = input.startPosition;
  }

  return body;
}

export function withPlayMethod(
  body: PlaybackStartRequest,
  method: PlayMethod | null | undefined,
): PlaybackStartRequest {
  if (!method) {
    const { play_method: _omit, ...rest } = body;
    return rest;
  }
  return { ...body, play_method: method };
}
