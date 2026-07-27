import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

const rootDir = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(readFileSync(join(rootDir, "package.json"), "utf8")) as {
  version: string;
};

export default defineConfig({
  plugins: [react()],
  base: "./",
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },
  build: {
    outDir: "dist",
    sourcemap: true,
    target: "es2019",
    cssCodeSplit: false,
  },
  server: {
    host: true,
    port: 5174,
  },
  test: {
    environment: "jsdom",
    globals: true,
    include: ["src/**/*.test.ts"],
    // Gate logic modules at 90% across statements/branches/functions/lines.
    // UI screens and native AVPlay/Starfish adapters stay excluded.
    coverage: {
      provider: "v8",
      reporter: ["text", "json-summary"],
      include: [
        "src/api/**/*.ts",
        "src/storage/**/*.ts",
        "src/discovery/**/*.ts",
        "src/focus/**/*.ts",
        "src/settings/playbackSettings.ts",
        "src/settings/subtitleAppearance.ts",
        "src/player/createPlayer.ts",
        "src/player/createMediaPlayer.ts",
        "src/player/timeFormat.ts",
        "src/player/subtitleFormats.ts",
        "src/platform/detect.ts",
        "src/platform/tizen/subtitleOverlay.ts",
        "src/platform/tizen/downloadSubtitle.ts",
        "src/platform/tizen/avplayTracks.ts",
        "src/update/**/*.ts",
      ],
      exclude: ["src/**/*.test.ts"],
      thresholds: {
        statements: 90,
        branches: 90,
        functions: 90,
        lines: 90,
      },
    },
  },
});
