/**
 * Download a remote subtitle file into the widget's private temp storage so
 * AVPlay can load it via setExternalSubtitlePath (absolute local path only).
 */

export interface TizenDownloadRequestConstructor {
  new (url: string, destination?: string, fileName?: string): unknown;
}

export interface TizenDownloadManager {
  start(
    request: unknown,
    callbacks?: {
      onprogress?: (id: number, received: number, total: number) => void;
      oncompleted?: (id: number, fullPath: string) => void;
      onfailed?: (id: number, error: { message?: string } | string) => void;
    },
  ): number;
  cancel?: (id: number) => void;
}

export interface TizenDownloadApi {
  DownloadRequest: TizenDownloadRequestConstructor;
  download: TizenDownloadManager;
}

function getTizenDownload(): TizenDownloadApi | null {
  const tizen = (window as unknown as { tizen?: TizenDownloadApi }).tizen;
  if (!tizen?.DownloadRequest || !tizen.download?.start) return null;
  return tizen;
}

/** Guess a local filename so AVPlay sees a recognizable subtitle extension. */
export function subtitleLocalFileName(url: string, label?: string): string {
  try {
    const path = new URL(url, "https://local.invalid").pathname;
    const base = path.split("/").pop() || "";
    if (/\.(smi|sami|srt|vtt|ttml|dfxp|xml)$/i.test(base)) {
      return base.replace(/[^\w.-]+/g, "_");
    }
  } catch {
    /* fall through */
  }
  const safe = (label || "subtitle").replace(/[^\w.-]+/g, "_").slice(0, 40);
  return `${safe || "subtitle"}.smi`;
}

/**
 * Download `url` into `wgt-private-tmp` and resolve with the absolute local path.
 * Rejects when the Tizen Download API is unavailable or the download fails.
 */
export function downloadSubtitleToLocalPath(
  url: string,
  label?: string,
  api: TizenDownloadApi | null = getTizenDownload(),
): Promise<string> {
  if (!api) {
    return Promise.reject(new Error("Tizen Download API is not available"));
  }
  const fileName = subtitleLocalFileName(url, label);
  const request = new api.DownloadRequest(url, "wgt-private-tmp", fileName);

  return new Promise((resolve, reject) => {
    try {
      api.download.start(request, {
        oncompleted: (_id, fullPath) => {
          if (!fullPath) {
            reject(new Error("Subtitle download completed without a path"));
            return;
          }
          resolve(fullPath);
        },
        onfailed: (_id, error) => {
          const message =
            typeof error === "string" ? error : error?.message || "Subtitle download failed";
          reject(new Error(message));
        },
      });
    } catch (err) {
      reject(err instanceof Error ? err : new Error(String(err)));
    }
  });
}
