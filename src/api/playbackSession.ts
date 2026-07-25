import { apiRequest, buildStreamUrl } from "./client";
import { sessionClient } from "./sessionClient";
import type { AudioSwitchResponse } from "../player/types";
import type { PrairieSession } from "../storage/session";

export async function reportPlaybackProgress(
  session: PrairieSession,
  playbackSessionId: string,
  position: number,
  isPaused: boolean,
  fetchImpl?: typeof fetch,
): Promise<void> {
  await apiRequest<void>(
    sessionClient(session, fetchImpl),
    `/api/v1/playback/${encodeURIComponent(playbackSessionId)}/progress`,
    {
      method: "POST",
      body: JSON.stringify({ position, is_paused: isPaused }),
    },
  );
}

export async function stopPlaybackSession(
  session: PrairieSession,
  playbackSessionId: string,
  fetchImpl?: typeof fetch,
): Promise<void> {
  await apiRequest<void>(
    sessionClient(session, fetchImpl),
    `/api/v1/playback/${encodeURIComponent(playbackSessionId)}`,
    { method: "DELETE" },
  );
}

export async function switchPlaybackAudio(
  session: PrairieSession,
  playbackSessionId: string,
  audioTrackIndex: number,
  position: number,
  fetchImpl?: typeof fetch,
): Promise<AudioSwitchResponse> {
  return apiRequest<AudioSwitchResponse>(
    sessionClient(session, fetchImpl),
    `/api/v1/playback/${encodeURIComponent(playbackSessionId)}/audio`,
    {
      method: "PATCH",
      body: JSON.stringify({
        audio_track_index: audioTrackIndex,
        position,
      }),
    },
  );
}

export function resolveMediaUrl(
  serverUrl: string,
  path: string,
  accessToken: string,
): string {
  return buildStreamUrl(serverUrl, path, accessToken);
}
