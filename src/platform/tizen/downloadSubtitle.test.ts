import { describe, expect, it, vi } from "vitest";
import {
  assertAllowedSubtitleDownloadUrl,
  downloadSubtitleToLocalPath,
  subtitleLocalFileName,
  type TizenDownloadApi,
} from "./downloadSubtitle";

const SERVER = "https://prairie.example";

function mockApi(overrides: Partial<TizenDownloadApi["download"]> = {}): TizenDownloadApi {
  const start =
    overrides.start ??
    vi.fn((_req: unknown, callbacks?: { oncompleted?: (id: number, fullPath: string) => void }) => {
      callbacks?.oncompleted?.(1, "/opt/usr/home/owner/apps_rw/tmp/track.vtt");
      return 1;
    });
  return {
    DownloadRequest: vi.fn(function DownloadRequest() {
      return {};
    }) as unknown as TizenDownloadApi["DownloadRequest"],
    download: {
      ...overrides,
      start,
    },
  };
}

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

describe("assertAllowedSubtitleDownloadUrl", () => {
  it("allows same-origin http(s) URLs", () => {
    expect(() =>
      assertAllowedSubtitleDownloadUrl("https://prairie.example/api/v1/subs/1.vtt", SERVER),
    ).not.toThrow();
  });

  it("rejects cross-origin and non-http URLs", () => {
    expect(() =>
      assertAllowedSubtitleDownloadUrl("https://evil.example/track.vtt", SERVER),
    ).toThrow(/same-origin/i);
    expect(() => assertAllowedSubtitleDownloadUrl("file:///tmp/x.vtt", SERVER)).toThrow(
      /http or https/i,
    );
    expect(() =>
      assertAllowedSubtitleDownloadUrl("https://prairie.example/a.vtt", null),
    ).toThrow(/connected server/i);
  });
});

describe("downloadSubtitleToLocalPath", () => {
  it("rejects when the Download API is missing", async () => {
    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/a.vtt", "en", {
        allowedServerUrl: SERVER,
        api: null,
      }).promise,
    ).rejects.toThrow(/not available/i);
  });

  it("rejects cross-origin URLs before starting a download", async () => {
    const api = mockApi();
    await expect(
      downloadSubtitleToLocalPath("https://evil.example/track.vtt", "en", {
        allowedServerUrl: SERVER,
        api,
      }).promise,
    ).rejects.toThrow(/same-origin/i);
    expect(api.download.start).not.toHaveBeenCalled();
  });

  it("resolves with the downloaded absolute path", async () => {
    const api = mockApi();
    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", {
        allowedServerUrl: SERVER,
        api,
      }).promise,
    ).resolves.toBe("/opt/usr/home/owner/apps_rw/tmp/track.vtt");
  });

  it("rejects on download failure and supports cancel", async () => {
    const cancel = vi.fn();
    const api = mockApi({
      start: (_req, callbacks) => {
        callbacks?.onfailed?.(1, { message: "network" });
        return 9;
      },
      cancel,
    });
    const handle = downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", {
      allowedServerUrl: SERVER,
      api,
    });
    await expect(handle.promise).rejects.toThrow("network");

    const pending = mockApi({
      start: () => 42,
      cancel,
    });
    const open = downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", {
      allowedServerUrl: SERVER,
      api: pending,
    });
    open.cancel();
    expect(cancel).toHaveBeenCalledWith(42);
  });

  it("rejects when completed without a path or when start throws", async () => {
    const emptyPath = mockApi({
      start: (_req, callbacks) => {
        callbacks?.oncompleted?.(1, "");
        return 1;
      },
    });
    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/a.vtt", "en", {
        allowedServerUrl: SERVER,
        api: emptyPath,
      }).promise,
    ).rejects.toThrow(/without a path/i);

    const throws = mockApi({
      start: () => {
        throw new Error("boom");
      },
    });
    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/a.vtt", "en", {
        allowedServerUrl: SERVER,
        api: throws,
      }).promise,
    ).rejects.toThrow("boom");
  });
});
