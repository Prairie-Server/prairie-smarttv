import { apiRequest } from "./client";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

export interface FileVersion {
  file_id: number;
  resolution?: string | null;
  codec_video?: string | null;
  codec_audio?: string | null;
  container?: string | null;
  duration?: number | null;
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
