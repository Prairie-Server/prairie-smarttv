import { apiRequest, buildStreamUrl, isSameServerOrigin } from "./client";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

export interface LiveTvChannel {
  id: string;
  tuner_id: string;
  number: string;
  number_override?: string | null;
  callsign: string;
  name: string;
  logo_url?: string;
  hd: boolean;
  enabled: boolean;
  stream_url?: string;
  guide_station_id?: string;
}

export interface LiveTvProgram {
  id: string;
  channel_id: string;
  start: string;
  stop: string;
  title: string;
  subtitle?: string;
  description?: string;
  season?: number | null;
  episode?: number | null;
  is_new?: boolean;
  is_live?: boolean;
  image_url?: string;
}

export type LiveTvTransport = "mpegts" | "hls";

export interface LiveTvSessionStart {
  session_id: string;
  playback_ticket?: string;
  hls_url?: string;
  stream_url?: string;
  transport?: LiveTvTransport;
  note?: string;
}

export interface LiveTvRecording {
  id: string;
  program_id?: string;
  channel_id: string;
  status: string;
  start: string;
  stop: string;
  title: string;
  library_item_id?: string;
}

/** Guide-based schedule: server resolves channel/window/title from program_id. */
export interface ScheduleLiveTvRecordingInput {
  program_id: string;
}

function looksLikeHlsUrl(url: string): boolean {
  const lower = url.toLowerCase();
  return lower.includes(".m3u8") || lower.includes("live-hls");
}

/** True when the session exposes an HLS stream Smart TV can play. */
export function isWatchableHls(start: LiveTvSessionStart): boolean {
  const url = playableLiveUrl(start);
  if (!url) return false;
  return start.transport === "hls" || looksLikeHlsUrl(url);
}

/** Prefer HLS URLs; MPEG-TS proxy paths are returned only when no HLS is available. */
export function playableLiveUrl(start: LiveTvSessionStart): string | null {
  const hls = (start.hls_url || "").trim();
  const stream = (start.stream_url || "").trim();

  if (start.transport === "hls") {
    return hls || stream || null;
  }

  if (hls && looksLikeHlsUrl(hls)) return hls;
  if (stream && looksLikeHlsUrl(stream)) return stream;
  if (hls) return hls;
  if (start.transport === "mpegts") {
    return stream || null;
  }
  return stream || null;
}

/**
 * Resolve a Live TV stream for playback. Only same-origin absolute URLs and
 * relative paths (joined via buildStreamUrl) are allowed — raw external tuner
 * URLs must be proxied by the Prairie server.
 */
export function resolveLivePlaybackUrl(
  serverUrl: string,
  streamPath: string,
  token: string | null,
  profileId?: string | null,
): string {
  const trimmed = streamPath.trim();
  if (!trimmed) {
    throw new Error("Live TV session returned no stream URL");
  }
  const isAbsoluteHttp = trimmed.startsWith("http://") || trimmed.startsWith("https://");
  if (isAbsoluteHttp && !isSameServerOrigin(serverUrl, trimmed)) {
    throw new Error("Live TV requires a server-proxied stream");
  }
  return buildStreamUrl(serverUrl, trimmed, token, profileId);
}

export async function fetchLiveTvChannels(
  session: PrairieSession,
  fetchImpl?: typeof fetch,
): Promise<LiveTvChannel[]> {
  try {
    const data = await apiRequest<{ channels?: LiveTvChannel[] }>(
      sessionClient(session, fetchImpl),
      "/api/v1/livetv/channels",
    );
    return (data.channels ?? []).filter((ch) => ch.enabled !== false);
  } catch (err) {
    // Feature absent on older servers — treat as empty rather than hard-failing shell.
    if (
      err &&
      typeof err === "object" &&
      "status" in err &&
      (err as { status: number }).status === 404
    ) {
      return [];
    }
    throw err;
  }
}

export async function fetchLiveTvGuide(
  session: PrairieSession,
  channelIds: string[],
  fetchImpl?: typeof fetch,
): Promise<LiveTvProgram[]> {
  if (!channelIds.length) return [];
  const params = new URLSearchParams();
  params.set("channels", channelIds.join(","));
  const data = await apiRequest<{ programs?: LiveTvProgram[] }>(
    sessionClient(session, fetchImpl),
    `/api/v1/livetv/guide?${params.toString()}`,
  );
  return data.programs ?? [];
}

export async function startLiveTvSession(
  session: PrairieSession,
  channelId: string,
  fetchImpl?: typeof fetch,
): Promise<LiveTvSessionStart> {
  return apiRequest<LiveTvSessionStart>(
    sessionClient(session, fetchImpl),
    `/api/v1/livetv/channels/${encodeURIComponent(channelId)}/session`,
    { method: "POST", body: "{}" },
  );
}

export async function releaseLiveTvSession(
  session: PrairieSession,
  liveSessionId: string,
  fetchImpl?: typeof fetch,
): Promise<void> {
  await apiRequest<unknown>(
    sessionClient(session, fetchImpl),
    `/api/v1/livetv/sessions/${encodeURIComponent(liveSessionId)}`,
    { method: "DELETE" },
  );
}

export async function fetchLiveTvRecordings(
  session: PrairieSession,
  fetchImpl?: typeof fetch,
): Promise<LiveTvRecording[]> {
  try {
    const data = await apiRequest<{ recordings?: LiveTvRecording[] }>(
      sessionClient(session, fetchImpl),
      "/api/v1/livetv/recordings",
    );
    return data.recordings ?? [];
  } catch (err) {
    if (
      err &&
      typeof err === "object" &&
      "status" in err &&
      (err as { status: number }).status === 404
    ) {
      return [];
    }
    throw err;
  }
}

export async function scheduleLiveTvRecording(
  session: PrairieSession,
  input: ScheduleLiveTvRecordingInput,
  fetchImpl?: typeof fetch,
): Promise<LiveTvRecording> {
  const programId = input.program_id?.trim();
  if (!programId) {
    throw new Error("Missing program id");
  }
  return apiRequest<LiveTvRecording>(
    sessionClient(session, fetchImpl),
    "/api/v1/livetv/recordings",
    { method: "POST", body: JSON.stringify({ program_id: programId }) },
  );
}

export async function cancelLiveTvRecording(
  session: PrairieSession,
  recordingId: string,
  fetchImpl?: typeof fetch,
): Promise<void> {
  const id = recordingId.trim();
  if (!id) {
    throw new Error("Missing recording id");
  }
  await apiRequest<unknown>(
    sessionClient(session, fetchImpl),
    `/api/v1/livetv/recordings/${encodeURIComponent(id)}`,
    { method: "DELETE" },
  );
}

export function channelDisplayLabel(channel: LiveTvChannel): string {
  const name = channel.name?.trim() || channel.callsign?.trim();
  return name || `Channel ${channel.number_override || channel.number}`;
}

function programsForChannel(programs: LiveTvProgram[], channelId: string): LiveTvProgram[] {
  return programs
    .filter((p) => p.channel_id === channelId)
    .slice()
    .sort((a, b) => Date.parse(a.start) - Date.parse(b.start));
}

/** Pick the program airing "now" for a channel from a guide window. */
export function currentProgramForChannel(
  programs: LiveTvProgram[],
  channelId: string,
  nowMs: number = Date.now(),
): LiveTvProgram | null {
  for (const program of programsForChannel(programs, channelId)) {
    const start = Date.parse(program.start);
    const stop = Date.parse(program.stop);
    if (Number.isFinite(start) && Number.isFinite(stop) && start <= nowMs && nowMs < stop) {
      return program;
    }
  }
  return null;
}

/** Pick the next upcoming program after "now" for a channel. */
export function nextProgramForChannel(
  programs: LiveTvProgram[],
  channelId: string,
  nowMs: number = Date.now(),
): LiveTvProgram | null {
  for (const program of programsForChannel(programs, channelId)) {
    const start = Date.parse(program.start);
    if (Number.isFinite(start) && start > nowMs) {
      return program;
    }
  }
  return null;
}
