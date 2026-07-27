import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  base: "./",
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
    environment: "happy-dom",
    globals: true,
    pool: "forks",
    fileParallelism: true,
    maxWorkers: "50%",
    include: ["src/**/*.test.ts"],
    // Gate logic modules at 95% across statements/branches/functions/lines.
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
      ],
      exclude: ["src/**/*.test.ts"],
      thresholds: {
        statements: 95,
        branches: 95,
        functions: 95,
        lines: 95,
      },
    },
  },
});
