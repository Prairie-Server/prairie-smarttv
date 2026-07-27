import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource/sora/400.css";
import "@fontsource/sora/600.css";
import "@fontsource/fraunces/600.css";
import "@fontsource/fraunces/700.css";
import "./styles.css";
import { App } from "./App";
import { detectImageFormats } from "./lib/imageFormats";
import { applyPerformanceTier } from "./perf/performanceTier";
import { restoreDurableStorage, scheduleDurablePersist } from "./storage/durableStorage";
import { ensureStorageSchema } from "./storage/persist";
import { migrateFromLegacy } from "./storage/serverRegistry";

async function boot() {
  // Restore mirrored servers/settings before schema/session reads when the
  // WebView localStorage was wiped by a sideload reinstall.
  await restoreDurableStorage();
  // Additive migrations only — never wipe session/settings on upgrade.
  ensureStorageSchema();
  migrateFromLegacy();
  scheduleDurablePersist();
  applyPerformanceTier();
  void detectImageFormats();

  const root = document.getElementById("root");
  if (!root) {
    throw new Error("Missing #root");
  }

  // Avoid React StrictMode double-mount in production TV builds — it races
  // playback/start + DELETE and surfaces PLAYER_ERR_CONNECTION_FAILED.
  const tree = import.meta.env.DEV ? (
    <StrictMode>
      <App />
    </StrictMode>
  ) : (
    <App />
  );
  createRoot(root).render(tree);
}

void boot();
