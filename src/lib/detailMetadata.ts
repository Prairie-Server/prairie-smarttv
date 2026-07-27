import type { EpisodeSummary, ItemDetail, ItemVersion } from "../api/catalog";

export type FactToken =
  | { kind: "text"; value: string }
  | { kind: "chip"; value: string }
  | { kind: "score"; value: string };

function preferredVersion(detail: ItemDetail): ItemVersion | null {
  const versions = detail.versions ?? [];
  if (!versions.length) return null;
  const lastId = detail.user_data?.last_file_id;
  if (lastId != null) {
    const match = versions.find((v) => v.file_id === lastId);
    if (match) return match;
  }
  return versions[0] ?? null;
}

export function formatRuntimeMinutes(runtimeMinutes: number | null | undefined): string | null {
  if (runtimeMinutes == null || runtimeMinutes <= 0) return null;
  if (runtimeMinutes < 60) return `${runtimeMinutes}m`;
  const h = Math.floor(runtimeMinutes / 60);
  const m = runtimeMinutes % 60;
  return m > 0 ? `${h}h ${m}m` : `${h}h`;
}

export function formatRuntimeSeconds(seconds: number | null | undefined): string | null {
  if (seconds == null || seconds <= 0) return null;
  return formatRuntimeMinutes(Math.round(seconds / 60));
}

export function typeLabel(type: string): string {
  switch (type.toLowerCase()) {
    case "movie":
      return "Movie";
    case "series":
    case "show":
    case "tv":
      return "TV Show";
    case "episode":
      return "Episode";
    case "season":
      return "Season";
    default:
      return type.charAt(0).toUpperCase() + type.slice(1);
  }
}

export function isSeriesType(type: string | undefined | null): boolean {
  if (!type) return false;
  const t = type.toLowerCase();
  return t === "series" || t === "show" || t === "tv";
}

export function seriesYearLabel(detail: ItemDetail): string | null {
  const first = detail.first_air_date?.slice(0, 4);
  const last = detail.last_air_date?.slice(0, 4);
  if (first && last && first !== last) return `${first}–${last}`;
  if (first) return first;
  if (detail.year && detail.year > 0) return String(detail.year);
  return null;
}

function resolutionLabel(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const lower = raw.toLowerCase();
  if (lower.includes("2160") || lower.includes("4k")) return "4K";
  if (lower.includes("1080") || lower.includes("720")) return "HD";
  if (lower.includes("480")) return "SD";
  return null;
}

function audioLabel(version: ItemVersion): string | null {
  const tracks = version.audio_tracks ?? [];
  const track = tracks.find((t) => t.default) ?? tracks[0];
  if (!track) {
    const codec = version.codec_audio?.toLowerCase() ?? "";
    if (codec.includes("atmos")) return "ATMOS";
    return null;
  }
  const layout = (track.layout ?? "").toLowerCase();
  if (layout.includes("atmos")) return "ATMOS";
  if (layout.includes("7.1")) return "7.1";
  if (layout.includes("5.1")) return "5.1";
  if (layout.includes("stereo") || layout === "2.0") return null;
  if (track.channels === 8) return "7.1";
  if (track.channels === 6) return "5.1";
  return null;
}

function qualityChips(version: ItemVersion | null): FactToken[] {
  if (!version) return [];
  const chips: FactToken[] = [];
  const res = resolutionLabel(version.resolution);
  if (res) chips.push({ kind: "chip", value: res });
  if (version.hdr) chips.push({ kind: "chip", value: "HDR" });
  const audio = audioLabel(version);
  if (audio) chips.push({ kind: "chip", value: audio });
  if ((version.subtitle_tracks?.length ?? 0) > 0) chips.push({ kind: "chip", value: "CC" });
  return chips;
}

export function movieFacts(detail: ItemDetail): FactToken[] {
  const tokens: FactToken[] = [];
  if (detail.year && detail.year > 0) tokens.push({ kind: "text", value: String(detail.year) });
  const runtime = formatRuntimeMinutes(detail.runtime);
  if (runtime) tokens.push({ kind: "text", value: runtime });
  if (detail.rating_imdb != null) {
    tokens.push({ kind: "score", value: detail.rating_imdb.toFixed(1) });
  }
  tokens.push(...qualityChips(preferredVersion(detail)));
  return tokens;
}

export function seriesFacts(detail: ItemDetail, seasonCount?: number | null): FactToken[] {
  const tokens: FactToken[] = [];
  const year = seriesYearLabel(detail);
  if (year) tokens.push({ kind: "text", value: year });
  const seasons = seasonCount ?? detail.season_count;
  if (seasons != null && seasons > 0) {
    tokens.push({ kind: "text", value: `${seasons} Season${seasons === 1 ? "" : "s"}` });
  }
  if (detail.episode_count != null && detail.episode_count > 0) {
    tokens.push({
      kind: "text",
      value: `${detail.episode_count} Episode${detail.episode_count === 1 ? "" : "s"}`,
    });
  }
  if (detail.rating_imdb != null) {
    tokens.push({ kind: "score", value: detail.rating_imdb.toFixed(1) });
  }
  return tokens;
}

export function sourceTokens(detail: ItemDetail): string[] {
  const tokens = [typeLabel(detail.type)];
  if (detail.genres?.length) tokens.push(...detail.genres.slice(0, 2));
  return tokens;
}

export function starringText(detail: ItemDetail): string | null {
  const names = (detail.cast ?? [])
    .slice(0, 3)
    .map((c) => c.name)
    .filter(Boolean);
  if (!names.length) return null;
  return `Starring ${names.join(", ")}`;
}

export function crewLine(detail: ItemDetail): string | null {
  const crew = detail.crew ?? [];
  const directors = crew.filter((c) => /director|creator/i.test(c.job)).map((c) => c.name);
  const unique = [...new Set(directors)].slice(0, 3);
  if (!unique.length) return null;
  const label = isSeriesType(detail.type) ? "Created by" : "Directed by";
  return `${label} ${unique.join(", ")}`;
}

export function resumePositionSeconds(
  position: number | null | undefined,
  duration: number | null | undefined,
): number | undefined {
  if (position == null || position <= 0) return undefined;
  if (duration != null && duration > 0 && position / duration >= 0.95) return undefined;
  return position;
}

export function hasResumeProgress(
  position: number | null | undefined,
  duration: number | null | undefined,
  isInProgress?: boolean | null,
): boolean {
  if (isInProgress) return true;
  const seconds = resumePositionSeconds(position, duration);
  return seconds != null && seconds > 30;
}

export function formatResumeLabel(positionSeconds: number): string {
  const total = Math.floor(positionSeconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) {
    return `Resume ${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  }
  return `Resume ${m}:${String(s).padStart(2, "0")}`;
}

export function pickNextUpEpisode(episodes: EpisodeSummary[]): EpisodeSummary | null {
  if (!episodes.length) return null;
  const inProgress = episodes.find((ep) => ep.user_data?.is_in_progress);
  if (inProgress) return inProgress;
  const unwatched = episodes.find((ep) => !(ep.user_data?.played ?? false));
  if (unwatched) return unwatched;
  return episodes[0] ?? null;
}

export function episodeProgressRatio(episode: EpisodeSummary): number | null {
  const position = episode.user_data?.position_seconds;
  const duration =
    episode.user_data?.duration_seconds ?? (episode.runtime ? episode.runtime * 60 : null);
  if (position == null || duration == null || duration <= 0) return null;
  const ratio = position / duration;
  if (ratio <= 0.02 || ratio >= 0.95) return null;
  return ratio;
}

export function formatAirDate(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return raw.slice(0, 10);
  return date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}
