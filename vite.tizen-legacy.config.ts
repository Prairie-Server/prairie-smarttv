import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import legacy from "@vitejs/plugin-legacy";

/**
 * Tizen 5.5 (Chromium ~M69) build: SystemJS + Babel downlevel.
 * Separate package id / config lives in platforms/tizen-legacy/.
 */
export default defineConfig({
  plugins: [
    react(),
    legacy({
      // Chrome 69 ≈ Tizen 5.5 WebKit/Chromium generation.
      targets: ["chrome >= 69"],
      modernPolyfills: true,
      additionalLegacyPolyfills: ["regenerator-runtime/runtime"],
      renderLegacyChunks: true,
    }),
  ],
  base: "./",
  build: {
    outDir: "dist-tizen-legacy-web",
    emptyOutDir: true,
    sourcemap: true,
    cssCodeSplit: false,
    cssTarget: "chrome69",
  },
  server: {
    host: true,
    port: 5175,
  },
});
