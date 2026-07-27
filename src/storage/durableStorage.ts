/**
 * Durable key/value mirror for packaged TV apps.
 *
 * Tizen/webOS WebView localStorage is wiped on many sideload reinstalls.
 * Moonfin webOS uses Luna DB8; on Tizen they still use localStorage — store
 * updates keep the same package id so data survives. Prairie mirrors preserved
 * keys into the Tizen documents folder (when available) so a localStorage wipe
 * can be restored on the next boot without changing package id (`PrairieApp`).
 */

import {
  LAST_SERVER_URL_KEY,
  PLAYBACK_SETTINGS_KEY,
  SERVER_REGISTRY_KEY,
  SESSION_KEY,
  STORAGE_SCHEMA_KEY,
} from "./persist";

const MIRROR_KEYS = [
  SESSION_KEY,
  LAST_SERVER_URL_KEY,
  SERVER_REGISTRY_KEY,
  PLAYBACK_SETTINGS_KEY,
  STORAGE_SCHEMA_KEY,
  "prairie.session.accessToken",
  "prairie.session.profileToken",
] as const;

const MIRROR_FILE = "prairie-durable-storage.json";

type MirrorMap = Record<string, string>;

interface TizenFile {
  openStream(
    mode: string,
    onsuccess: (stream: TizenFileStream) => void,
    onerror?: (err: unknown) => void,
    encoding?: string,
  ): void;
  readAsText(
    onsuccess: (text: string) => void,
    onerror?: (err: unknown) => void,
    encoding?: string,
  ): void;
}

interface TizenFileStream {
  write(data: string): void;
  close(): void;
}

interface TizenFileHandle {
  createFile?(name: string): TizenFile;
  resolve?(path: string): TizenFile;
  listFiles?(
    onsuccess: (files: Array<{ name: string; isFile: boolean }>) => void,
    onerror?: (err: unknown) => void,
  ): void;
}

function tizenDocuments(): TizenFileHandle | null {
  try {
    const fs = (
      window as unknown as {
        tizen?: { filesystem?: { resolve: (path: string) => TizenFileHandle } };
      }
    ).tizen?.filesystem;
    if (!fs?.resolve) return null;
    return fs.resolve("documents");
  } catch {
    return null;
  }
}

function readMirrorFile(dir: TizenFileHandle): Promise<MirrorMap> {
  return new Promise((resolve) => {
    try {
      dir.listFiles?.(
        (files) => {
          const hit = files.find((f) => f.isFile && f.name === MIRROR_FILE);
          if (!hit) {
            resolve({});
            return;
          }
          let file: TizenFile | null = null;
          try {
            file = dir.resolve?.(MIRROR_FILE) ?? null;
          } catch {
            resolve({});
            return;
          }
          file?.readAsText(
            (text) => {
              try {
                const parsed = JSON.parse(text) as MirrorMap;
                resolve(parsed && typeof parsed === "object" ? parsed : {});
              } catch {
                resolve({});
              }
            },
            () => resolve({}),
            "UTF-8",
          );
        },
        () => resolve({}),
      );
    } catch {
      resolve({});
    }
  });
}

function writeMirrorFile(dir: TizenFileHandle, data: MirrorMap): void {
  try {
    let file: TizenFile | null = null;
    try {
      file = dir.resolve?.(MIRROR_FILE) ?? null;
    } catch {
      file = dir.createFile?.(MIRROR_FILE) ?? null;
    }
    if (!file) {
      try {
        file = dir.createFile?.(MIRROR_FILE) ?? null;
      } catch {
        return;
      }
    }
    file?.openStream(
      "w",
      (stream) => {
        try {
          stream.write(JSON.stringify(data));
        } finally {
          stream.close();
        }
      },
      () => undefined,
      "UTF-8",
    );
  } catch {
    /* best-effort */
  }
}

/** Restore mirrored keys into localStorage when the WebView store was wiped. */
export async function restoreDurableStorage(
  storage: Pick<Storage, "getItem" | "setItem"> = localStorage,
): Promise<number> {
  const dir = tizenDocuments();
  if (!dir) return 0;
  const mirror = await readMirrorFile(dir);
  let restored = 0;
  for (const key of MIRROR_KEYS) {
    const value = mirror[key];
    if (typeof value !== "string" || !value) continue;
    if (storage.getItem(key)) continue;
    storage.setItem(key, value);
    restored += 1;
  }
  return restored;
}

/** Snapshot preserved keys into the durable mirror (Tizen documents). */
export function persistDurableStorage(storage: Pick<Storage, "getItem"> = localStorage): void {
  const dir = tizenDocuments();
  if (!dir) return;
  const data: MirrorMap = {};
  for (const key of MIRROR_KEYS) {
    const value = storage.getItem(key);
    if (value != null) data[key] = value;
  }
  writeMirrorFile(dir, data);
}

/** Call after any localStorage write of preserved keys. */
export function scheduleDurablePersist(): void {
  window.setTimeout(() => {
    try {
      persistDurableStorage();
    } catch {
      /* ignore */
    }
  }, 0);
}
