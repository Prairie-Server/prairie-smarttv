/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_DEFAULT_SERVER_URL?: string;
}

interface AvPlayApi {
  open(url: string): void;
  close(): void;
  prepare(): void;
  prepareAsync(success?: () => void, error?: (err: unknown) => void): void;
  setDisplayRect(x: number, y: number, width: number, height: number): void;
  setListener(listener: Record<string, unknown>): void;
  play(): void;
  pause(): void;
  stop(): void;
  getState(): string;
  getDuration(): number;
  getCurrentTime(): number;
  seekTo(milliseconds: number, success?: () => void, error?: (err: unknown) => void): void;
}

declare global {
  interface Window {
    webapis?: {
      avplay?: AvPlayApi;
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
