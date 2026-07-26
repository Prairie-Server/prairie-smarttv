import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource/sora/400.css";
import "@fontsource/sora/600.css";
import "@fontsource/fraunces/600.css";
import "@fontsource/fraunces/700.css";
import "./styles.css";
import { App } from "./App";
import { ensureStorageSchema } from "./storage/persist";
import { migrateFromLegacy } from "./storage/serverRegistry";

// Additive migrations only — never wipe session/settings on upgrade.
ensureStorageSchema();
migrateFromLegacy();

const root = document.getElementById("root");
if (!root) {
  throw new Error("Missing #root");
}

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
