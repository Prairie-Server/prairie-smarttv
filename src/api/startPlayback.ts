import { apiRequest, buildStreamUrl } from "./client";
import { buildPlaybackStartRequest, type BuildPlaybackStartInput } from "./playback";
import type { PlaybackSessionResponse } from "../player/types";
import type { ForcedPlayMethod } from "../platform/types";

export async function startPlayback(
  serverUrl: string,
  accessToken: string,
  input: BuildPlaybackStartInput,
  fetchImpl?: typeof fetch,
): Promise<PlaybackSessionResponse> {
  const body = buildPlaybackStartRequest(input);
  return apiRequest<PlaybackSessionResponse>(
    { serverUrl, accessToken, fetchImpl },
    "/api/v1/playback/start",
    {
      method: "POST",
      body: JSON.stringify(body),
    },
  );
}

export function resolvePlaybackStreamUrl(
  serverUrl: string,
  session: PlaybackSessionResponse,
  accessToken: string,
): string {
  return buildStreamUrl(serverUrl, session.stream_url, accessToken);
}

export type { ForcedPlayMethod, BuildPlaybackStartInput };
