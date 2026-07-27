import { ApiError, apiRequest, buildStreamUrl } from "./client";
import { sessionClient } from "./sessionClient";
import type {
  PlaybackSessionResponse,
  TranscodeStartRequest,
  TranscodeStartResponse,
} from "../player/types";
import type { PrairieSession } from "../storage/session";

/** Remux/transcode sessions need an HLS encode job before the player has a real URL. */
export function needsHlsBootstrap(playMethod: string | null | undefined): boolean {
  const method = (playMethod ?? "").trim().toLowerCase();
  return method === "remux" || method === "transcode";
}

export function buildTranscodeStartRequest(input: {
  sessionId: string;
  seekSeconds: number;
  playMethod: string;
}): TranscodeStartRequest {
  const isRemux = input.playMethod.trim().toLowerCase() === "remux";
  return {
    session_id: input.sessionId,
    seek_seconds: Math.max(0, input.seekSeconds),
    // Remux = container remux with codec copy (TV can usually passthrough audio).
    // Transcode = conservative 1080p h264/aac ladder default (matches Apple fallback).
    target_resolution: isRemux ? "" : "1080p",
    target_codec_video: isRemux ? "copy" : "h264",
    target_codec_audio: isRemux ? "copy" : "aac",
    target_bitrate_kbps: isRemux ? 0 : 6000,
    segment_duration: 2,
    subtitle_track_index: -1,
    subtitle_burn_in: false,
  };
}

export async function startTranscode(
  session: PrairieSession,
  body: TranscodeStartRequest,
  fetchImpl?: typeof fetch,
): Promise<TranscodeStartResponse> {
  return apiRequest<TranscodeStartResponse>(
    sessionClient(session, fetchImpl),
    "/api/v1/playback/transcode/start",
    {
      method: "POST",
      body: JSON.stringify(body),
    },
  );
}

export interface PreparedPlayback {
  session: PlaybackSessionResponse;
  streamUrl: string;
  /** Prefer this when seeking/resuming after HLS bootstrap. */
  playerStartSeconds: number;
}

/**
 * Mirror web/Apple/Android legacy: after /playback/start, remux and transcode
 * must POST /playback/transcode/start and play `manifest_url` (not the
 * informational placeholder `stream_url`).
 */
export async function preparePlayableSession(
  session: PrairieSession,
  started: PlaybackSessionResponse,
  seekSeconds: number,
  fetchImpl?: typeof fetch,
): Promise<PreparedPlayback> {
  if (!needsHlsBootstrap(started.play_method)) {
    return {
      session: started,
      streamUrl: buildStreamUrl(session.serverUrl, started.stream_url, session.accessToken),
      playerStartSeconds: seekSeconds,
    };
  }

  let transcode: TranscodeStartResponse;
  try {
    transcode = await startTranscode(
      session,
      buildTranscodeStartRequest({
        sessionId: started.session_id,
        seekSeconds,
        playMethod: started.play_method,
      }),
      fetchImpl,
    );
  } catch (err) {
    // Older servers may reject remux copy (422). Fall back to a real encode.
    const isRemux = started.play_method.trim().toLowerCase() === "remux";
    if (!isRemux || !(err instanceof ApiError) || err.status !== 422) throw err;
    transcode = await startTranscode(
      session,
      {
        session_id: started.session_id,
        seek_seconds: Math.max(0, seekSeconds),
        target_resolution: "1080p",
        target_codec_video: "h264",
        target_codec_audio: "aac",
        target_bitrate_kbps: 6000,
        segment_duration: 2,
        subtitle_track_index: -1,
        subtitle_burn_in: false,
      },
      fetchImpl,
    );
  }

  const playMethod = transcode.can_seek_anywhere ? "transcode" : "remux";
  const next: PlaybackSessionResponse = {
    ...started,
    session_id: transcode.session_id || started.session_id,
    play_method: playMethod,
    stream_url: transcode.manifest_url,
    position: transcode.player_start_seconds ?? started.position,
    duration_seconds: transcode.duration_seconds ?? started.duration_seconds,
    playback_info: {
      ...started.playback_info,
      stream_type: "hls",
      can_seek_anywhere: transcode.can_seek_anywhere ?? started.playback_info?.can_seek_anywhere,
    },
  };

  return {
    session: next,
    streamUrl: buildStreamUrl(session.serverUrl, transcode.manifest_url, session.accessToken),
    playerStartSeconds: transcode.player_start_seconds ?? seekSeconds,
  };
}
