import { describe, expect, it, vi } from "vitest";
import {
  persistDurableStorage,
  restoreDurableStorage,
  scheduleDurablePersist,
} from "./durableStorage";
import { SESSION_KEY, STORAGE_SCHEMA_KEY } from "./persist";

describe("durableStorage", () => {
  it("no-ops restore/persist when Tizen filesystem is unavailable", async () => {
    const storage = {
      getItem: vi.fn(() => null),
      setItem: vi.fn(),
    };
    await expect(restoreDurableStorage(storage)).resolves.toBe(0);
    expect(storage.setItem).not.toHaveBeenCalled();
    persistDurableStorage({ getItem: () => "x" });
  });

  it("skips the mirror read entirely when the store is already populated", async () => {
    // A populated store means no wipe happened; boot must not pay the Tizen
    // filesystem read (and its first-paint delay) to recover nothing.
    const getItem = vi.fn((key: string) => (key === STORAGE_SCHEMA_KEY ? "3" : null));
    const storage = { getItem, setItem: vi.fn() };
    await expect(restoreDurableStorage(storage)).resolves.toBe(0);
    expect(getItem).toHaveBeenCalledWith(STORAGE_SCHEMA_KEY);
    expect(storage.setItem).not.toHaveBeenCalled();
  });

  it("treats a session with no schema key as a live store, not a wipe", async () => {
    // A sideload wipe clears localStorage wholesale, so any surviving preserved
    // key means no wipe happened. Restoring over a live store would resurrect
    // keys the app deliberately cleared (a logout drops the session but leaves
    // the mirror until the next persist tick).
    const getItem = vi.fn((key: string) => (key === SESSION_KEY ? "{}" : null));
    const storage = { getItem, setItem: vi.fn() };
    await expect(restoreDurableStorage(storage)).resolves.toBe(0);
    expect(storage.setItem).not.toHaveBeenCalled();
  });

  it("schedules a best-effort persist tick", async () => {
    vi.useFakeTimers();
    scheduleDurablePersist();
    await vi.runAllTimersAsync();
    vi.useRealTimers();
  });
});
