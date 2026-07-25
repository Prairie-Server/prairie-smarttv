import type { PlayMethod, ResolvedPlayerBackend } from "../platform/types";

export interface MediaPlayer {
  play(): void | Promise<void>;
  pause(): void;
  destroy(): void;
  backend: ResolvedPlayerBackend;
}

export interface CreateMediaPlayerOptions {
  url: string;
  container: HTMLElement;
  backend: ResolvedPlayerBackend;
  autoplay?: boolean;
  onError?: (message: string) => void;
  onEnded?: () => void;
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
}

/** Conservative TV capability advertisement for foundation playback. */
export const DEFAULT_TV_CAPABILITIES = {
  codecs_video: ["h264", "hevc"],
  codecs_audio: ["aac", "ac3", "eac3", "mp3"],
  containers: ["mp4", "mpegts", "hls", "mkv"],
  max_resolution: "2160p",
  hdr: true,
} as const;
