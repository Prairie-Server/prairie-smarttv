import { StrictMode, Suspense } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource/sora/latin-400.css";
import "@fontsource/sora/latin-600.css";
import "@fontsource/fraunces/latin-600.css";
import "@fontsource/fraunces/latin-700.css";
import "./styles.css";
import { App } from "./App";
import { detectImageFormats } from "./lib/imageFormats";
import { applyPerformanceTier } from "./perf/performanceTier";
import { startHomePrefetch } from "./api/homePrefetch";
import { registerRemoteMediaKeys } from "./platform/remoteKeys";
import { restoreDurableStorageWithBudget, scheduleDurablePersist } from "./storage/durableStorage";
import { ensureStorageSchema } from "./storage/persist";
import { loadSession } from "./storage/session";
import { migrateFromLegacy } from "./storage/serverRegistry";
import { watchViewportScale } from "./ui/viewportScale";

async function boot() {
  // Ask for Home rows first thing: it is the slow network leg and needs only the
  // synchronous session read, so kick it off before the durable restore's
  // filesystem read (and the rest of boot) instead of serializing behind them.
  // On a wiped install the session is absent here, so nothing is fetched until
  // the restore + reload seeds it — exactly the case where there is nothing to
  // prefetch anyway.
  const restored = loadSession();
  if (restored) startHomePrefetch(restored);

  // Restore mirrored servers/settings when the WebView localStorage was wiped by
  // a sideload reinstall — but never let that filesystem read hold the first
  // paint hostage (it now short-circuits entirely on a populated store). A late
  // restore reloads the app, which only happens on a wiped install with a saved
  // session.
  await restoreDurableStorageWithBudget(() => window.location.reload());
  // Additive migrations only — never wipe session/settings on upgrade.
  ensureStorageSchema();
  migrateFromLegacy();
  scheduleDurablePersist();
  applyPerformanceTier();
  // Claim the media transport keys before any player mounts, otherwise Tizen
  // answers Play/Pause with its own on-screen media helper.
  registerRemoteMediaKeys();
  watchViewportScale();
  void detectImageFormats();

  const root = document.getElementById("root");
  if (!root) {
    throw new Error("Missing #root");
  }

  // Route-level Suspense lives inside App so the shell/nav stays mounted while
  // a lazy screen chunk loads. Keep a root boundary only as a safety net for
  // anything that suspends outside those gates.
  const app = (
    <Suspense fallback={<div className="screen" aria-busy="true" />}>
      <App />
    </Suspense>
  );

  // Avoid React StrictMode double-mount in production TV builds — it races
  // playback/start + DELETE and surfaces PLAYER_ERR_CONNECTION_FAILED.
  const tree = import.meta.env.DEV ? <StrictMode>{app}</StrictMode> : app;
  createRoot(root).render(tree);
}

void boot();
