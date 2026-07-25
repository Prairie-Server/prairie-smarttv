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
  onError?: (message: string) => void;
  onEnded?: () => void;
  onTimeUpdate?: (currentSeconds: number, durationSeconds: number) => void;
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

/** Conservative TV capability advertisement for foundation playback. */
export const DEFAULT_TV_CAPABILITIES = {
  codecs_video: ["h264", "hevc"],
  codecs_audio: ["aac", "ac3", "eac3", "mp3"],
  containers: ["mp4", "mpegts", "hls", "mkv"],
  max_resolution: "2160p",
  hdr: true,
} as const;
