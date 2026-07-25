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

export interface SubtitleDownloadHandle {
  promise: Promise<string>;
  cancel: () => void;
}

function getTizenDownload(): TizenDownloadApi | null {
  const tizen = (window as unknown as { tizen?: TizenDownloadApi }).tizen;
  if (!tizen?.DownloadRequest || !tizen.download?.start) return null;
  return tizen;
}

function extensionFromUrl(url: string): string {
  try {
    const path = new URL(url, "https://local.invalid").pathname;
    const base = path.split("/").pop() || "";
    const match = base.match(/\.(smi|sami|srt|vtt|ttml|dfxp)$/i);
    if (match) return match[0]!.toLowerCase();
  } catch {
    /* fall through */
  }
  return ".smi";
}

/** Unique local filename so concurrent downloads cannot overwrite each other. */
export function subtitleLocalFileName(url: string, label?: string): string {
  const ext = extensionFromUrl(url);
  const safe = (label || "subtitle").replace(/[^\w.-]+/g, "_").slice(0, 24) || "subtitle";
  const stamp = `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
  return `${safe}_${stamp}${ext}`;
}

/**
 * Download `url` into `wgt-private-tmp` and resolve with the absolute local path.
 * Call `cancel()` to abort a superseded download when the Tizen API supports it.
 */
export function downloadSubtitleToLocalPath(
  url: string,
  label?: string,
  api: TizenDownloadApi | null = getTizenDownload(),
): SubtitleDownloadHandle {
  if (!api) {
    return {
      promise: Promise.reject(new Error("Tizen Download API is not available")),
      cancel: () => undefined,
    };
  }

  const fileName = subtitleLocalFileName(url, label);
  const request = new api.DownloadRequest(url, "wgt-private-tmp", fileName);
  let downloadId: number | null = null;
  let settled = false;

  const promise = new Promise<string>((resolve, reject) => {
    try {
      downloadId = api.download.start(request, {
        oncompleted: (_id, fullPath) => {
          settled = true;
          if (!fullPath) {
            reject(new Error("Subtitle download completed without a path"));
            return;
          }
          resolve(fullPath);
        },
        onfailed: (_id, error) => {
          settled = true;
          const message =
            typeof error === "string" ? error : error?.message || "Subtitle download failed";
          reject(new Error(message));
        },
      });
    } catch (err) {
      settled = true;
      reject(err instanceof Error ? err : new Error(String(err)));
    }
  });

  return {
    promise,
    cancel: () => {
      if (settled || downloadId == null) return;
      try {
        api.download.cancel?.(downloadId);
      } catch {
        /* ignore */
      }
    },
  };
}

/** Convenience for callers that only need the path promise. */
export function downloadSubtitlePath(
  url: string,
  label?: string,
  api: TizenDownloadApi | null = getTizenDownload(),
): Promise<string> {
  return downloadSubtitleToLocalPath(url, label, api).promise;
}
