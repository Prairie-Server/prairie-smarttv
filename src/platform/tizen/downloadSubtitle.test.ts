import { describe, expect, it, vi } from "vitest";
import {
  downloadSubtitleToLocalPath,
  subtitleLocalFileName,
  type TizenDownloadApi,
} from "./downloadSubtitle";

describe("subtitleLocalFileName", () => {
  it("keeps known subtitle extensions and makes unique names", () => {
    const a = subtitleLocalFileName("https://example/a/b/track.vtt?token=1", "English");
    const b = subtitleLocalFileName("https://example/a/b/track.vtt?token=1", "English");
    expect(a).toMatch(/^English_.+\.vtt$/);
    expect(b).toMatch(/^English_.+\.vtt$/);
    expect(a).not.toBe(b);
    expect(subtitleLocalFileName("https://example/subs/en.srt")).toMatch(/\.srt$/);
  });

  it("falls back to .smi when the URL has no extension", () => {
    expect(subtitleLocalFileName("https://example/api/v1/sub/1", "English")).toMatch(
      /^English_.+\.smi$/,
    );
  });
});

describe("downloadSubtitleToLocalPath", () => {
  it("rejects when the Download API is missing", async () => {
    await expect(downloadSubtitleToLocalPath("https://x/a.vtt", "en", null).promise).rejects.toThrow(
      /not available/i,
    );
  });

  it("resolves with the downloaded absolute path", async () => {
    const api: TizenDownloadApi = {
      DownloadRequest: vi.fn(function DownloadRequest() {
        return {};
      }) as unknown as TizenDownloadApi["DownloadRequest"],
      download: {
        start: (_req, callbacks) => {
          callbacks?.oncompleted?.(1, "/opt/usr/home/owner/apps_rw/tmp/track.vtt");
          return 1;
        },
      },
    };
    await expect(downloadSubtitleToLocalPath("https://x/track.vtt", "en", api).promise).resolves.toBe(
      "/opt/usr/home/owner/apps_rw/tmp/track.vtt",
    );
  });

  it("rejects on download failure and supports cancel", async () => {
    const cancel = vi.fn();
    const api: TizenDownloadApi = {
      DownloadRequest: vi.fn(function DownloadRequest() {
        return {};
      }) as unknown as TizenDownloadApi["DownloadRequest"],
      download: {
        start: (_req, callbacks) => {
          callbacks?.onfailed?.(1, { message: "network" });
          return 9;
        },
        cancel,
      },
    };
    const handle = downloadSubtitleToLocalPath("https://x/track.vtt", "en", api);
    await expect(handle.promise).rejects.toThrow("network");

    const pending: TizenDownloadApi = {
      DownloadRequest: vi.fn(function DownloadRequest() {
        return {};
      }) as unknown as TizenDownloadApi["DownloadRequest"],
      download: {
        start: () => 42,
        cancel,
      },
    };
    const open = downloadSubtitleToLocalPath("https://x/track.vtt", "en", pending);
    open.cancel();
    expect(cancel).toHaveBeenCalledWith(42);
  });

  it("rejects when completed without a path or when start throws", async () => {
    const emptyPath: TizenDownloadApi = {
      DownloadRequest: vi.fn(function DownloadRequest() {
        return {};
      }) as unknown as TizenDownloadApi["DownloadRequest"],
      download: {
        start: (_req, callbacks) => {
          callbacks?.oncompleted?.(1, "");
          return 1;
        },
      },
    };
    await expect(
      downloadSubtitleToLocalPath("https://x/a.vtt", "en", emptyPath).promise,
    ).rejects.toThrow(/without a path/i);

    const throws: TizenDownloadApi = {
      DownloadRequest: vi.fn(function DownloadRequest() {
        return {};
      }) as unknown as TizenDownloadApi["DownloadRequest"],
      download: {
        start: () => {
          throw new Error("boom");
        },
      },
    };
    await expect(downloadSubtitleToLocalPath("https://x/a.vtt", "en", throws).promise).rejects.toThrow(
      "boom",
    );
  });
});
