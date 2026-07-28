import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import legacy from "@vitejs/plugin-legacy";

const rootDir = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(readFileSync(join(rootDir, "package.json"), "utf8")) as {
  version: string;
};

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
      // Chrome 69 cannot execute the es2019+ modern chunks (optional chaining,
      // nullish coalescing land in Chrome 80), so emitting them alongside the
      // legacy set only doubled the JS packaged into the .wgt and parsed from
      // flash on the weakest hardware. Legacy-only for this single-target build.
      renderModernChunks: false,
    }),
  ],
  base: "./",
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },
  resolve: {
    alias: {
      "hls.js": join(rootDir, "node_modules/hls.js/dist/hls.light.mjs"),
    },
  },
  build: {
    outDir: "dist-tizen-legacy-web",
    emptyOutDir: true,
    // Sourcemaps stay out of the TV package; it is read from flash on launch.
    sourcemap: false,
    cssCodeSplit: false,
    cssTarget: "chrome69",
  },
  server: {
    host: true,
    port: 5175,
  },
});
