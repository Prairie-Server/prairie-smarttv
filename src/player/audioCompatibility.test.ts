import { describe, expect, it } from "vitest";
import {
  isAudioCodecSupported,
  normalizeAudioCodec,
  primaryAudioCodec,
  versionNeedsAudioRemux,
  watchFileNeedsAudioRemux,
} from "./audioCompatibility";
import type { WatchDetail } from "../api/watch";

describe("audioCompatibility", () => {
  const base = ["aac", "ac3", "eac3", "mp3"];

  it("normalizes codec labels", () => {
    expect(normalizeAudioCodec("TrueHD")).toBe("truehd");
    expect(normalizeAudioCodec("e-ac-3")).toBe("eac3");
    expect(normalizeAudioCodec(null)).toBe("");
  });

  it("matches advertised codecs and aliases", () => {
    expect(isAudioCodecSupported("aac", base)).toBe(true);
    expect(isAudioCodecSupported("e-ac-3", base)).toBe(true);
    expect(isAudioCodecSupported("ac3", ["eac3"])).toBe(true);
    expect(isAudioCodecSupported("ac3", ["ec3"])).toBe(true);
    expect(isAudioCodecSupported("ec3", ["eac3"])).toBe(true);
    expect(isAudioCodecSupported("truehd", base)).toBe(false);
    expect(isAudioCodecSupported("truehd", [...base, "truehd"])).toBe(true);
    expect(isAudioCodecSupported("truehd atmos", ["truehd"])).toBe(true);
    expect(isAudioCodecSupported("aac", ["aac "])).toBe(true);
    expect(isAudioCodecSupported("dts", ["truehd"])).toBe(false);
    expect(isAudioCodecSupported("", base)).toBe(true);
    expect(isAudioCodecSupported(null, base)).toBe(true);
  });

  it("detects when a version needs audio remux from capabilities", () => {
    expect(versionNeedsAudioRemux(null, base)).toBe(false);
    expect(versionNeedsAudioRemux({ file_id: 1, codec_audio: "aac", audio_tracks: [] }, base)).toBe(
      false,
    );
    expect(
      versionNeedsAudioRemux({ file_id: 2, codec_audio: "truehd", audio_tracks: [] }, base),
    ).toBe(true);
    expect(
      versionNeedsAudioRemux(
        {
          file_id: 3,
          codec_audio: null,
          audio_tracks: [{ codec: "dts", default: true }],
        },
        base,
      ),
    ).toBe(true);
    expect(
      versionNeedsAudioRemux(
        {
          file_id: 4,
          codec_audio: null,
          audio_tracks: [{ codec: "truehd", default: true }],
        },
        [...base, "truehd"],
      ),
    ).toBe(false);
    expect(
      versionNeedsAudioRemux(
        {
          file_id: 5,
          codec_audio: null,
          audio_tracks: [],
        },
        base,
      ),
    ).toBe(false);

    expect(primaryAudioCodec({ file_id: 5, codec_audio: "flac" })).toBe("flac");
    expect(primaryAudioCodec(null)).toBe(null);
    expect(primaryAudioCodec({ file_id: 6, audio_tracks: [{ codec: "opus" }] })).toBe("opus");
    expect(
      primaryAudioCodec({
        file_id: 7,
        audio_tracks: [
          { codec: "aac", default: false },
          { codec: "ac3", default: true },
        ],
      }),
    ).toBe("ac3");
    expect(primaryAudioCodec({ file_id: 8, audio_tracks: undefined })).toBe(null);

    const watch: WatchDetail = {
      content_id: "m1",
      type: "movie",
      title: "Roger Rabbit",
      versions: [{ file_id: 9, codec_audio: "truehd" }],
    };
    expect(watchFileNeedsAudioRemux(watch, 9, base)).toBe(true);
    expect(watchFileNeedsAudioRemux(watch, 9, [...base, "truehd"])).toBe(false);
    expect(watchFileNeedsAudioRemux(null, 9, base)).toBe(false);
    expect(watchFileNeedsAudioRemux(watch, 99, base)).toBe(false);
  });
});
