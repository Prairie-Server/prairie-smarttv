import { describe, expect, it, vi } from "vitest";
import {
  fetchWatchDetail,
  formatAudioLabel,
  formatSubtitleLabel,
  selectFileVersion,
  selectPlaybackFileId,
  type WatchDetail,
} from "./watch";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
};

function watch(partial: Partial<WatchDetail> & Pick<WatchDetail, "versions">): WatchDetail {
  return {
    content_id: "tt1",
    type: "movie",
    title: "Test",
    ...partial,
  };
}

describe("selectPlaybackFileId", () => {
  it("returns null when there are no versions", () => {
    expect(selectPlaybackFileId(watch({ versions: [] }))).toBeNull();
  });

  it("prefers an explicit preferred file id when present", () => {
    expect(
      selectPlaybackFileId(
        watch({
          versions: [{ file_id: 1 }, { file_id: 9 }],
          user_data: { last_file_id: 1 },
        }),
        9,
      ),
    ).toBe(9);
  });

  it("falls back to last_file_id then the first version", () => {
    expect(
      selectPlaybackFileId(
        watch({
          versions: [{ file_id: 3 }, { file_id: 7 }],
          user_data: { last_file_id: 7 },
        }),
      ),
    ).toBe(7);

    expect(
      selectPlaybackFileId(
        watch({
          versions: [{ file_id: 3 }, { file_id: 7 }],
          user_data: { last_file_id: 99 },
        }),
      ),
    ).toBe(3);

    expect(
      selectPlaybackFileId(
        watch({
          versions: [{ file_id: 3 }],
        }),
        0,
      ),
    ).toBe(3);
  });
});

describe("fetchWatchDetail", () => {
  it("normalizes a missing versions array", async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response(
          JSON.stringify({
            content_id: "tt1",
            type: "movie",
            title: "Dune",
          }),
          { status: 200 },
        ),
    );

    const detail = await fetchWatchDetail(session, "tt1", fetchImpl);
    expect(detail.versions).toEqual([]);
    expect(detail.title).toBe("Dune");
    expect(fetchImpl).toHaveBeenCalledOnce();
  });
});

describe("watch helpers", () => {
  it("selects file versions and formats track labels", () => {
    const detail = watch({
      versions: [
        {
          file_id: 3,
          audio_tracks: [{ language: "eng", codec: "aac", channels: 2 }],
        },
      ],
    });
    expect(selectFileVersion(detail, 3)?.file_id).toBe(3);
    expect(selectFileVersion(detail, 9)).toBeNull();
    expect(formatAudioLabel({ language: "eng", channels: 6 }, 0)).toContain("eng");
    expect(formatAudioLabel({ title: "Commentary", embedded_title: "ignored" }, 0)).toContain(
      "Commentary",
    );
    expect(formatAudioLabel({}, 1)).toBe("Audio 2");
    expect(formatSubtitleLabel({ language: "spa", forced: true })).toContain("Forced");
    expect(formatSubtitleLabel({ title: "English", hearing_impaired: true })).toContain("HI");
    expect(formatSubtitleLabel({})).toBe("Subtitle");
  });
});
