import { afterEach, describe, expect, it, vi } from "vitest";
import { isSelectKey, registerRemoteMediaKeys, remoteKeyName } from "./remoteKeys";

type TizenGlobal = {
  tvinputdevice?: {
    registerKey?: (name: string) => void;
    getSupportedKeys?: () => Array<{ name?: string }>;
  };
};

function setTizen(value: TizenGlobal | undefined): void {
  (window as unknown as { tizen?: TizenGlobal }).tizen = value;
}

afterEach(() => {
  setTizen(undefined);
});

describe("remoteKeyName", () => {
  it("prefers a usable event.key", () => {
    expect(remoteKeyName({ key: "MediaPlayPause", keyCode: 0 })).toBe("MediaPlayPause");
  });

  it("maps Tizen vendor key codes when event.key is unusable", () => {
    expect(remoteKeyName({ key: "Unidentified", keyCode: 10252 })).toBe("MediaPlayPause");
    expect(remoteKeyName({ key: "", keyCode: 415 })).toBe("MediaPlay");
    expect(remoteKeyName({ key: "", keyCode: 19 })).toBe("MediaPause");
    expect(remoteKeyName({ key: "", keyCode: 10009 })).toBe("XF86Back");
  });

  it("maps the webOS Back key code", () => {
    expect(remoteKeyName({ key: "Unidentified", keyCode: 461 })).toBe("XF86Back");
  });

  it("returns an empty name for unknown codes", () => {
    expect(remoteKeyName({ key: "Unidentified", keyCode: 9999 })).toBe("");
  });
});

describe("isSelectKey", () => {
  it("covers the OK button spellings", () => {
    expect(isSelectKey("Enter")).toBe(true);
    expect(isSelectKey(" ")).toBe(true);
    expect(isSelectKey("Spacebar")).toBe(true);
    expect(isSelectKey("MediaPlayPause")).toBe(false);
  });
});

describe("registerRemoteMediaKeys", () => {
  it("is a no-op off Tizen", () => {
    expect(registerRemoteMediaKeys()).toEqual([]);
  });

  it("registers only the keys the TV reports as supported", () => {
    const registerKey = vi.fn();
    setTizen({
      tvinputdevice: {
        registerKey,
        getSupportedKeys: () => [{ name: "MediaPlayPause" }, { name: "MediaPlay" }],
      },
    });
    expect(registerRemoteMediaKeys()).toEqual(["MediaPlayPause", "MediaPlay"]);
    expect(registerKey).toHaveBeenCalledTimes(2);
  });

  it("registers blind and tolerates per-key failures when the key list is unavailable", () => {
    const registerKey = vi.fn((name: string) => {
      if (name === "MediaStop") throw new Error("unsupported");
    });
    setTizen({
      tvinputdevice: {
        registerKey,
        getSupportedKeys: () => {
          throw new Error("not implemented");
        },
      },
    });
    const registered = registerRemoteMediaKeys();
    expect(registered).toContain("MediaPlayPause");
    expect(registered).not.toContain("MediaStop");
  });
});
