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

export interface SubtitleDownloadOptions {
  /** Connected Prairie server — downloads must match this origin. */
  allowedServerUrl?: string | null;
  api?: TizenDownloadApi | null;
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

/** Reject non-http(s) and cross-origin subtitle URLs before Tizen Download starts. */
export function assertAllowedSubtitleDownloadUrl(
  url: string,
  allowedServerUrl?: string | null,
): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error("Subtitle URL is not a valid absolute URL");
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error("Subtitle URL must use http or https");
  }
  if (!allowedServerUrl) {
    throw new Error("Subtitle download requires a connected server origin");
  }
  let server: URL;
  try {
    server = new URL(allowedServerUrl);
  } catch {
    throw new Error("Connected server URL is invalid");
  }
  if (parsed.protocol !== server.protocol || parsed.host !== server.host) {
    throw new Error("Subtitle URL must be same-origin with the Prairie server");
  }
}

type TizenFsDir = {
  deleteFile?: (name: string, ok?: () => void, err?: () => void) => void;
};

type TizenFilesystem = {
  resolve?: (
    path: string,
    onsuccess: (file: TizenFsDir) => void,
    onerror?: () => void,
    mode?: string,
  ) => void;
};

/** Best-effort delete of a file previously downloaded into wgt-private-tmp. */
export function deleteLocalSubtitleFile(fullPath: string): void {
  if (!fullPath) return;
  try {
    const fs = (window as unknown as { tizen?: { filesystem?: TizenFilesystem } }).tizen
      ?.filesystem;
    if (!fs?.resolve) return;

    const slash = fullPath.lastIndexOf("/");
    if (slash <= 0) return;
    const dirPath = fullPath.slice(0, slash);
    const fileName = fullPath.slice(slash + 1);
    if (!fileName) return;

    fs.resolve(
      dirPath,
      (dir) => {
        try {
          dir.deleteFile?.(fileName);
        } catch {
          /* ignore */
        }
      },
      () => undefined,
      "rw",
    );
  } catch {
    /* ignore — cleanup is best-effort on Tizen */
  }
}

/**
 * Download `url` into `wgt-private-tmp` and resolve with the absolute local path.
 * Call `cancel()` to abort a superseded download when the Tizen API supports it.
 */
export function downloadSubtitleToLocalPath(
  url: string,
  label?: string,
  options: SubtitleDownloadOptions | TizenDownloadApi | null = {},
): SubtitleDownloadHandle {
  // Back-compat: older call sites passed the API as the third argument.
  const normalized: SubtitleDownloadOptions =
    options == null
      ? { api: null }
      : typeof (options as TizenDownloadApi).DownloadRequest === "function"
        ? { api: options as TizenDownloadApi }
        : (options as SubtitleDownloadOptions);

  const api = normalized.api === undefined ? getTizenDownload() : normalized.api;

  try {
    assertAllowedSubtitleDownloadUrl(url, normalized.allowedServerUrl);
  } catch (err) {
    return {
      promise: Promise.reject(err instanceof Error ? err : new Error(String(err))),
      cancel: () => undefined,
    };
  }

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
  options: SubtitleDownloadOptions | TizenDownloadApi | null = {},
): Promise<string> {
  return downloadSubtitleToLocalPath(url, label, options).promise;
}
