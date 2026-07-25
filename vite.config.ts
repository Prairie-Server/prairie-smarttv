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
    environment: "jsdom",
    globals: true,
    include: ["src/**/*.test.ts"],
    // Gate coverage on unit-tested core modules only. UI/screens and native
    // player adapters stay out of the threshold until they gain tests.
    coverage: {
      provider: "v8",
      reporter: ["text", "json-summary"],
      include: [
        "src/api/client.ts",
        "src/api/playback.ts",
        "src/settings/playbackSettings.ts",
        "src/player/createPlayer.ts",
      ],
      thresholds: {
        statements: 75,
        branches: 70,
        functions: 75,
        lines: 75,
      },
    },
  },
});
