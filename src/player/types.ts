import type { PlayMethod, ResolvedPlayerBackend } from "../platform/types";

export interface MediaPlayer {
  play(): void | Promise<void>;
  pause(): void;
  destroy(): void;
  backend: ResolvedPlayerBackend;
  /** Seek to an absolute media time in seconds. */
  seekTo(seconds: number): void | Promise<void>;
  getCurrentTime(): number;
  getDuration(): number;
  /**
   * Side-load a text subtitle track (VTT/SRT URL). Pass null to disable.
   * Native backends that cannot render text tracks no-op safely.
   */
  setTextTrack(url: string | null, label?: string): void | Promise<void>;
}

export interface CreateMediaPlayerOptions {
  url: string;
  container: HTMLElement;
  backend: ResolvedPlayerBackend;
  autoplay?: boolean;
  mimeType?: string;
  /** AVPlay: attach this external subtitle in IDLE before prepare. */
  initialSubtitleUrl?: string | null;
  initialSubtitleLabel?: string;
  /** Connected Prairie origin — gates Tizen subtitle downloads. */
  allowedServerUrl?: string | null;
  onError?: (message: string) => void;
  onEnded?: () => void;
  onTimeUpdate?: (currentSeconds: number, durationSeconds: number) => void;
  /** Native players: buffering started/finished. */
  onBuffering?: (active: boolean) => void;
}

export interface SubtitleUrlEntry {
  index: number;
  language?: string;
  codec?: string;
  label?: string;
  source?: string;
  forced?: boolean;
  hearing_impaired?: boolean;
  url: string;
  font_bundle_url?: string;
}

export interface PlaybackStartRequest {
  file_id: number;
  profile_id: string;
  codecs_video: string[];
  codecs_audio: string[];
  containers: string[];
  max_resolution: string;
  hdr: boolean;
  play_method?: PlayMethod;
  start_position?: number;
  audio_track_index?: number;
  supports_bitmap_subtitle_burn_in?: boolean;
}

export interface PlaybackSessionResponse {
  session_id: string;
  user_id: number;
  profile_id: string;
  media_file_id: number;
  play_method: string;
  position: number;
  is_paused: boolean;
  stream_url: string;
  audio_track_index: number;
  duration_seconds?: number | null;
  subtitle_urls?: SubtitleUrlEntry[];
  playback_info?: {
    stream_type?: string;
    can_seek_anywhere?: boolean;
    /** Remux should re-encode audio (typically AAC) instead of copy. */
    transcode_audio?: boolean;
    video_codec?: string;
    audio_codec?: string;
  };
}

export interface AudioSwitchResponse {
  audio_track_index: number;
  play_method: string;
  stream_url: string;
  switch_mode?: string;
  player_start_seconds?: number;
  stream_origin_seconds?: number;
  can_seek_anywhere?: boolean;
}

/** Request body for POST /api/v1/playback/transcode/start. */
export interface TranscodeStartRequest {
  session_id: string;
  seek_seconds: number;
  target_resolution: string;
  /**
   * `"copy"` for remux. Omit on encode so the server selects
   * best(client.codecs_video ∩ encodableCodecs).
   */
  target_codec_video?: string;
  target_codec_audio: string;
  target_bitrate_kbps: number;
  segment_duration: number;
  subtitle_track_index: number;
  subtitle_media_file_id?: number;
  subtitle_burn_in: boolean;
}

/** Response from POST /api/v1/playback/transcode/start. */
export interface TranscodeStartResponse {
  session_id: string;
  status: string;
  switched_file_id?: number;
  manifest_url: string;
  duration_seconds?: number | null;
  player_start_seconds?: number;
  stream_origin_seconds?: number;
  timeline_offset_seconds?: number;
  can_seek_anywhere?: boolean;
}

/** Conservative TV capability advertisement for foundation playback. */
export const DEFAULT_TV_CAPABILITIES = {
  codecs_video: ["h264", "hevc"],
  codecs_audio: ["aac", "ac3", "eac3", "mp3"],
  containers: ["mp4", "mpegts", "hls", "mkv"],
  max_resolution: "2160p",
  hdr: true,
} as const;
