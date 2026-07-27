import { describe, expect, it } from "vitest";
import {
  isTvSafeAudioCodec,
  requiresForcedTranscodeAudio,
  versionRequiresForcedTranscode,
  watchFileRequiresForcedTranscode,
} from "./audioCompatibility";
import type { WatchDetail } from "../api/watch";

describe("audioCompatibility", () => {
  it("treats common TV codecs as safe", () => {
    expect(isTvSafeAudioCodec("aac")).toBe(true);
    expect(isTvSafeAudioCodec("ac3")).toBe(true);
    expect(isTvSafeAudioCodec("e-ac-3")).toBe(true);
    expect(isTvSafeAudioCodec("")).toBe(true);
    expect(isTvSafeAudioCodec(null)).toBe(true);
    expect(requiresForcedTranscodeAudio("aac")).toBe(false);
    expect(requiresForcedTranscodeAudio("")).toBe(false);
  });

  it("forces transcode for TrueHD / DTS / FLAC / PCM", () => {
    expect(requiresForcedTranscodeAudio("truehd")).toBe(true);
    expect(requiresForcedTranscodeAudio("TrueHD")).toBe(true);
    expect(requiresForcedTranscodeAudio("mlp")).toBe(true);
    expect(requiresForcedTranscodeAudio("dts-hd")).toBe(true);
    expect(requiresForcedTranscodeAudio("flac")).toBe(true);
    expect(requiresForcedTranscodeAudio("opus")).toBe(true);
    expect(requiresForcedTranscodeAudio("pcm_s24le")).toBe(true);
    expect(requiresForcedTranscodeAudio("unknown-codec")).toBe(true);
  });

  it("inspects watch file versions and tracks", () => {
    expect(versionRequiresForcedTranscode(null)).toBe(false);
    expect(
      versionRequiresForcedTranscode({
        file_id: 1,
        codec_audio: "aac",
        audio_tracks: [],
      }),
    ).toBe(false);
    expect(
      versionRequiresForcedTranscode({
        file_id: 2,
        codec_audio: "aac",
        audio_tracks: [
          { codec: "aac", language: "eng" },
          { codec: "truehd", language: "eng", default: true },
        ],
      }),
    ).toBe(true);

    const watch: WatchDetail = {
      content_id: "m1",
      type: "movie",
      title: "Roger Rabbit",
      versions: [
        {
          file_id: 9,
          codec_video: "hevc",
          codec_audio: "truehd",
          audio_tracks: [{ codec: "truehd", language: "eng", default: true }],
        },
      ],
    };
    expect(versionRequiresForcedTranscode(watch.versions[0])).toBe(true);
    expect(watchFileRequiresForcedTranscode(watch, 9)).toBe(true);
    expect(watchFileRequiresForcedTranscode(watch, 99)).toBe(false);
    expect(watchFileRequiresForcedTranscode(null, 9)).toBe(false);
  });
});
