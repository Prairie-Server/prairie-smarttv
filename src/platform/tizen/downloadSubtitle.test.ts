import { describe, expect, it, vi, afterEach } from "vitest";
import {
  assertAllowedSubtitleDownloadUrl,
  deleteLocalSubtitleFile,
  downloadSubtitlePath,
  downloadSubtitleToLocalPath,
  extensionFromSubtitleFormat,
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

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("extensionFromSubtitleFormat", () => {
  it("maps codec and format strings to extensions", () => {
    expect(extensionFromSubtitleFormat(null)).toBeNull();
    expect(extensionFromSubtitleFormat(undefined)).toBeNull();
    expect(extensionFromSubtitleFormat("")).toBeNull();
    expect(extensionFromSubtitleFormat("   ")).toBeNull();
    expect(extensionFromSubtitleFormat(".srt")).toBe(".srt");
    expect(extensionFromSubtitleFormat("VTT")).toBe(".vtt");
    expect(extensionFromSubtitleFormat("webvtt")).toBe(".vtt");
    expect(extensionFromSubtitleFormat("subrip")).toBe(".srt");
    expect(extensionFromSubtitleFormat("srt")).toBe(".srt");
    expect(extensionFromSubtitleFormat("sami")).toBe(".sami");
    expect(extensionFromSubtitleFormat("smi")).toBe(".smi");
    expect(extensionFromSubtitleFormat("includes-sami-codec")).toBe(".smi");
    expect(extensionFromSubtitleFormat("application/ttml+xml")).toBe(".ttml");
    expect(extensionFromSubtitleFormat("dfxp")).toBe(".dfxp");
    expect(extensionFromSubtitleFormat("smpte-tt")).toBe(".ttml");
    expect(extensionFromSubtitleFormat("unknown")).toBeNull();
  });
});

describe("subtitleLocalFileName", () => {
  it("keeps known subtitle extensions and makes unique names", () => {
    const a = subtitleLocalFileName("https://example/a/b/track.vtt?token=1", "English");
    const b = subtitleLocalFileName("https://example/a/b/track.vtt?token=1", "English");
    expect(a).toMatch(/^English_.+\.vtt$/);
    expect(b).toMatch(/^English_.+\.vtt$/);
    expect(a).not.toBe(b);
    expect(subtitleLocalFileName("https://example/subs/en.srt")).toMatch(/\.srt$/);
  });

  it("uses format metadata when the URL has no extension", () => {
    expect(subtitleLocalFileName("https://example/api/v1/sub/1", "English", "srt")).toMatch(
      /^English_.+\.srt$/,
    );
    expect(subtitleLocalFileName("https://example/api/v1/sub/1?format=smi", "English")).toMatch(
      /^English_.+\.smi$/,
    );
    expect(subtitleLocalFileName("https://example/api/v1/sub/1?codec=webvtt", "English")).toMatch(
      /^English_.+\.vtt$/,
    );
  });

  it("defaults extensionless Prairie subtitle URLs to .vtt", () => {
    expect(subtitleLocalFileName("https://example/api/v1/sub/1", "English")).toMatch(
      /^English_.+\.vtt$/,
    );
  });

  it("sanitizes labels and recovers from relative URLs", () => {
    expect(subtitleLocalFileName("https://example/a.vtt", "!!!")).toMatch(/^_+.+\.vtt$/);
    expect(subtitleLocalFileName("not a url", "en", "ttml")).toMatch(/^en_.+\.ttml$/);
  });
});

describe("assertAllowedSubtitleDownloadUrl", () => {
  it("allows same-origin http(s) URLs", () => {
    expect(() =>
      assertAllowedSubtitleDownloadUrl("https://prairie.example/api/v1/subs/1.vtt", SERVER),
    ).not.toThrow();
    expect(() =>
      assertAllowedSubtitleDownloadUrl(
        "http://prairie.example/api/v1/subs/1.vtt",
        "http://prairie.example",
      ),
    ).not.toThrow();
  });

  it("rejects cross-origin and non-http URLs", () => {
    expect(() =>
      assertAllowedSubtitleDownloadUrl("https://evil.example/track.vtt", SERVER),
    ).toThrow(/same-origin/i);
    expect(() => assertAllowedSubtitleDownloadUrl("file:///tmp/x.vtt", SERVER)).toThrow(
      /http or https/i,
    );
    expect(() => assertAllowedSubtitleDownloadUrl("https://prairie.example/a.vtt", null)).toThrow(
      /connected server/i,
    );
    expect(() => assertAllowedSubtitleDownloadUrl("not-a-url", SERVER)).toThrow(
      /valid absolute URL/i,
    );
    expect(() => assertAllowedSubtitleDownloadUrl("https://prairie.example/a.vtt", ":::")).toThrow(
      /Connected server URL is invalid/i,
    );
  });
});

describe("deleteLocalSubtitleFile", () => {
  it("no-ops without a path or filesystem API", () => {
    expect(() => deleteLocalSubtitleFile("")).not.toThrow();
    expect(() => deleteLocalSubtitleFile("/tmp/file.vtt")).not.toThrow();
  });

  it("resolves and deletes when Tizen filesystem is available", () => {
    const deleteFile = vi.fn();
    const resolve = vi.fn(
      (_path: string, onsuccess: (file: { deleteFile?: typeof deleteFile }) => void) => {
        onsuccess({ deleteFile });
      },
    );
    vi.stubGlobal("window", {
      tizen: { filesystem: { resolve } },
    });
    deleteLocalSubtitleFile("/wgt-private-tmp/track.vtt");
    expect(resolve).toHaveBeenCalled();
    expect(deleteFile).toHaveBeenCalledWith("track.vtt");

    deleteLocalSubtitleFile("noslash");
    deleteLocalSubtitleFile("/onlydir/");
    resolve.mockImplementation((_path, _ok, onerror) => onerror?.());
    expect(() => deleteLocalSubtitleFile("/wgt-private-tmp/track.vtt")).not.toThrow();

    resolve.mockImplementation((_path, onsuccess) => {
      onsuccess({
        deleteFile: () => {
          throw new Error("denied");
        },
      });
    });
    expect(() => deleteLocalSubtitleFile("/wgt-private-tmp/track.vtt")).not.toThrow();
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

  it("accepts legacy API-as-third-argument and null options", async () => {
    const api = mockApi();
    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", api).promise,
    ).rejects.toThrow(/connected server/i);

    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", null).promise,
    ).rejects.toThrow(/connected server/i);
  });

  it("uses window.tizen download when api is omitted", async () => {
    const api = mockApi();
    vi.stubGlobal("window", { tizen: api });
    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", {
        allowedServerUrl: SERVER,
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

    const stringFail = mockApi({
      start: (_req, callbacks) => {
        callbacks?.onfailed?.(1, "string-fail");
        return 8;
      },
    });
    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", {
        allowedServerUrl: SERVER,
        api: stringFail,
      }).promise,
    ).rejects.toThrow("string-fail");

    const emptyMsg = mockApi({
      start: (_req, callbacks) => {
        callbacks?.onfailed?.(1, {});
        return 7;
      },
    });
    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", {
        allowedServerUrl: SERVER,
        api: emptyMsg,
      }).promise,
    ).rejects.toThrow(/Subtitle download failed/i);

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

    // cancel after settle is a no-op
    handle.cancel();
    // cancel without downloadId
    const noId = mockApi({
      start: () => null as unknown as number,
      cancel,
    });
    const dangling = downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", {
      allowedServerUrl: SERVER,
      api: noId,
    });
    dangling.cancel();

    const throwingCancel = mockApi({
      start: () => 99,
      cancel: () => {
        throw new Error("cancel failed");
      },
    });
    const open2 = downloadSubtitleToLocalPath("https://prairie.example/track.vtt", "en", {
      allowedServerUrl: SERVER,
      api: throwingCancel,
    });
    expect(() => open2.cancel()).not.toThrow();
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

    const throwsNonError = mockApi({
      start: () => {
        throw "raw";
      },
    });
    await expect(
      downloadSubtitleToLocalPath("https://prairie.example/a.vtt", "en", {
        allowedServerUrl: SERVER,
        api: throwsNonError,
      }).promise,
    ).rejects.toThrow("raw");
  });

  it("exposes downloadSubtitlePath convenience", async () => {
    const api = mockApi();
    await expect(
      downloadSubtitlePath("https://prairie.example/track.vtt", "en", {
        allowedServerUrl: SERVER,
        api,
      }),
    ).resolves.toBe("/opt/usr/home/owner/apps_rw/tmp/track.vtt");
  });
});
