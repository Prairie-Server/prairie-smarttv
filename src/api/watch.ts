import type { ItemDetail } from "./catalog";
import { apiRequest } from "./client";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

export interface AudioTrackInfo {
  title?: string;
  embedded_title?: string;
  language?: string;
  codec?: string;
  layout?: string;
  channels?: number;
  default?: boolean;
}

export interface SubtitleTrackInfo {
  index?: number;
  language?: string;
  codec?: string;
  title?: string;
  embedded_title?: string;
  forced?: boolean;
  default?: boolean;
  hearing_impaired?: boolean;
  external?: boolean;
}

export interface FileVersion {
  file_id: number;
  resolution?: string | null;
  codec_video?: string | null;
  codec_audio?: string | null;
  container?: string | null;
  duration?: number | null;
  audio_tracks?: AudioTrackInfo[];
  subtitle_tracks?: SubtitleTrackInfo[];
}

export interface WatchUserData {
  played?: boolean;
  is_in_progress?: boolean;
  position_seconds?: number | null;
  duration_seconds?: number | null;
  last_file_id?: number | null;
}

export interface WatchDetail {
  content_id: string;
  type: string;
  title: string;
  overview?: string | null;
  poster_url?: string | null;
  backdrop_url?: string | null;
  year?: number | null;
  versions: FileVersion[];
  user_data?: WatchUserData | null;
  series_id?: string | null;
  season_number?: number | null;
  episode_number?: number | null;
}

export async function fetchWatchDetail(
  session: PrairieSession,
  contentId: string,
  fetchImpl?: typeof fetch,
): Promise<WatchDetail> {
  const data = await apiRequest<WatchDetail>(
    sessionClient(session, fetchImpl),
    `/api/v1/watch/${encodeURIComponent(contentId)}`,
  );
  return {
    ...data,
    versions: data.versions ?? [],
  };
}

/**
 * Build a WatchDetail from item-detail payload when versions are already present.
 * Avoids a second round-trip on Play for movies that just loaded their hero.
 */
export function watchDetailFromItemDetail(detail: ItemDetail): WatchDetail | null {
  const versions = detail.versions ?? [];
  if (versions.length === 0) return null;
  return {
    content_id: detail.content_id,
    type: detail.type || "movie",
    title: detail.title,
    overview: detail.overview,
    poster_url: detail.poster_url,
    backdrop_url: detail.backdrop_url,
    year: detail.year,
    versions: versions.map((version) => ({
      file_id: version.file_id,
      resolution: version.resolution,
      codec_video: version.codec_video,
      codec_audio: version.codec_audio,
      container: version.container,
      duration: version.duration,
      audio_tracks: version.audio_tracks,
      subtitle_tracks: version.subtitle_tracks,
    })),
    user_data: detail.user_data ?? undefined,
    series_id: detail.series_id,
    season_number: detail.season_number,
    episode_number: detail.episode_number,
  };
}

/** Pick a playable file_id from watch detail (preferred → last → first version). */
export function selectPlaybackFileId(
  watch: WatchDetail,
  preferredFileId?: number | null,
): number | null {
  const versions = watch.versions ?? [];
  if (!versions.length) return null;
  if (
    preferredFileId != null &&
    preferredFileId > 0 &&
    versions.some((v) => v.file_id === preferredFileId)
  ) {
    return preferredFileId;
  }
  const last = watch.user_data?.last_file_id;
  if (last != null && last > 0 && versions.some((v) => v.file_id === last)) {
    return last;
  }
  return versions[0]?.file_id ?? null;
}

export function selectFileVersion(watch: WatchDetail, fileId: number): FileVersion | null {
  return watch.versions.find((v) => v.file_id === fileId) ?? null;
}

export function formatAudioLabel(track: AudioTrackInfo, index: number): string {
  const parts = [
    track.language,
    track.title || track.embedded_title,
    track.codec,
    track.channels ? `${track.channels}ch` : null,
  ].filter(Boolean);
  return parts.length ? parts.join(" · ") : `Audio ${index + 1}`;
}

export function formatSubtitleLabel(track: {
  language?: string;
  label?: string;
  title?: string;
  hearing_impaired?: boolean;
  forced?: boolean;
}): string {
  const base = track.label || track.title || track.language || "Subtitle";
  const tags = [track.forced ? "Forced" : null, track.hearing_impaired ? "HI" : null].filter(
    Boolean,
  );
  return tags.length ? `${base} (${tags.join(", ")})` : base;
}
