import { describe, expect, it, vi } from "vitest";
import {
  downloadSubtitleToLocalPath,
  subtitleLocalFileName,
  type TizenDownloadApi,
} from "./downloadSubtitle";

describe("subtitleLocalFileName", () => {
  it("keeps known subtitle extensions from the URL", () => {
    expect(subtitleLocalFileName("https://example/a/b/track.vtt?token=1")).toBe("track.vtt");
    expect(subtitleLocalFileName("https://example/subs/en.srt")).toBe("en.srt");
  });

  it("falls back to a labeled .smi name", () => {
    expect(subtitleLocalFileName("https://example/api/v1/sub/1", "English")).toBe("English.smi");
  });
});

describe("downloadSubtitleToLocalPath", () => {
  it("rejects when the Download API is missing", async () => {
    await expect(downloadSubtitleToLocalPath("https://x/a.vtt", "en", null)).rejects.toThrow(
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
    await expect(downloadSubtitleToLocalPath("https://x/track.vtt", "en", api)).resolves.toBe(
      "/opt/usr/home/owner/apps_rw/tmp/track.vtt",
    );
  });

  it("rejects on download failure", async () => {
    const api: TizenDownloadApi = {
      DownloadRequest: vi.fn(function DownloadRequest() {
        return {};
      }) as unknown as TizenDownloadApi["DownloadRequest"],
      download: {
        start: (_req, callbacks) => {
          callbacks?.onfailed?.(1, { message: "network" });
          return 1;
        },
      },
    };
    await expect(downloadSubtitleToLocalPath("https://x/track.vtt", "en", api)).rejects.toThrow(
      "network",
    );
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
    await expect(downloadSubtitleToLocalPath("https://x/a.vtt", "en", emptyPath)).rejects.toThrow(
      /without a path/i,
    );

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
    await expect(downloadSubtitleToLocalPath("https://x/a.vtt", "en", throws)).rejects.toThrow(
      "boom",
    );
  });
});
