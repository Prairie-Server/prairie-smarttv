import { describe, expect, it, vi } from "vitest";
import {
  persistDurableStorage,
  restoreDurableStorage,
  scheduleDurablePersist,
} from "./durableStorage";

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

  it("schedules a best-effort persist tick", async () => {
    vi.useFakeTimers();
    scheduleDurablePersist();
    await vi.runAllTimersAsync();
    vi.useRealTimers();
  });
});
