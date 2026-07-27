/// <reference types="vite/client" />

interface AvPlayTrackInfo {
  type: string;
  index: number;
  extra_info?: string | Record<string, unknown>;
}

interface AvPlayApi {
  open(url: string): void;
  close(): void;
  prepare(): void;
  prepareAsync(success?: () => void, error?: (err: unknown) => void): void;
  setDisplayRect(x: number, y: number, width: number, height: number): void;
  setDisplayMethod?(displayMode: string): void;
  setStreamingProperty?(propertyType: string, propertyParam: string): void;
  setListener(listener: Record<string, unknown>): void;
  play(): void;
  pause(): void;
  stop(): void;
  getState(): string;
  getDuration(): number;
  getCurrentTime(): number;
  seekTo(milliseconds: number, success?: () => void, error?: (err: unknown) => void): void;
  setExternalSubtitlePath?(path: string): void;
  setSilentSubtitle?(silent: boolean): void;
  setSelectTrack?(type: string, index: number): void;
  getTotalTrackInfo?(): AvPlayTrackInfo[];
  setSubtitlePosition?(positionMs: number): void;
}

interface TvInfoApi {
  registerInAppCaptionControl?(enabled: boolean): void;
  showCaption?(show: boolean): void;
}

interface TizenDownloadRequestConstructor {
  new (url: string, destination?: string, fileName?: string): unknown;
}

interface TizenDownloadManager {
  start(
    request: unknown,
    callbacks?: {
      oncompleted?: (id: number, fullPath: string) => void;
      onfailed?: (id: number, error: { message?: string } | string) => void;
    },
  ): number;
}

declare global {
  /** Marketing semver injected from package.json via Vite `define`. */
  const __APP_VERSION__: string;

  // Augment Vite's ImportMetaEnv (must stay inside declare global while this
  // file is a module via `export {}`).
  interface ImportMetaEnv {
    readonly VITE_DEFAULT_SERVER_URL?: string;
  }

  interface Window {
    webapis?: {
      avplay?: AvPlayApi;
      tvinfo?: TvInfoApi;
      systeminfo?: {
        isSupportedAudioCodec?(codec: string): boolean;
        isSupportedVideoCodec?(codec: string): boolean;
      };
    };
    tizen?: {
      DownloadRequest: TizenDownloadRequestConstructor;
      download: TizenDownloadManager;
    };
    webOS?: {
      platform?: {
        tv?: boolean;
      };
    };
    PalmSystem?: unknown;
  }
}

export {};
