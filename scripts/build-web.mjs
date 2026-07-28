#!/usr/bin/env node
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const isWindows = process.platform === "win32";
const ALLOWED_PLATFORMS = new Set(["web", "tizen", "tizen-legacy", "webos"]);

const args = process.argv.slice(2);
const platformIdx = args.indexOf("--platform");
let platform = "web";

if (platformIdx !== -1) {
  const value = args[platformIdx + 1];
  if (!ALLOWED_PLATFORMS.has(value)) {
    console.error(
      `Invalid --platform "${value ?? ""}". Expected one of: web, tizen, tizen-legacy, webos.`,
    );
    process.exit(1);
  }
  platform = value;
} else {
  const positional = args.find((a) => ALLOWED_PLATFORMS.has(a));
  if (positional) platform = positional;
}

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, {
    cwd: root,
    stdio: "inherit",
    // Windows: npm is a .cmd shim; Node rejects direct .cmd spawn without a shell.
    shell: isWindows,
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

/**
 * Drop the WOFF 1.0 fallbacks from a TV package.
 *
 * @fontsource ships every face as woff2 + woff. Every TV WebView we target is
 * Chromium 69 or newer and woff2 has been supported since Chromium 36, so the
 * woff copies are dead weight (~80 kB) that ride along in the .wgt forever.
 * The `src:` fallback is stripped from the CSS too, so nothing points at a file
 * the package no longer contains.
 */
function pruneLegacyFonts(outDir) {
  const assets = join(outDir, "assets");
  if (!existsSync(assets)) return;

  let removedBytes = 0;
  for (const name of readdirSync(assets)) {
    if (!name.endsWith(".woff")) continue;
    const file = join(assets, name);
    removedBytes += statSync(file).size;
    rmSync(file);
  }
  if (removedBytes === 0) return;

  for (const name of readdirSync(assets)) {
    if (!name.endsWith(".css")) continue;
    const file = join(assets, name);
    const css = readFileSync(file, "utf8");
    // Only the trailing woff entry of a woff2-first `src:` list.
    const pruned = css.replace(/,url\([^)]*\.woff\)\s*format\((["']?)woff\1\)/g, "");
    if (pruned !== css) writeFileSync(file, pruned);
  }
  console.log(`Pruned WOFF 1.0 fallbacks (${(removedBytes / 1024).toFixed(1)} kB)`);
}

function copyPlatformAssets(platformName, outDir) {
  if (platformName === "tizen" || platformName === "tizen-legacy") {
    const platformDir = join(root, "platforms", platformName);
    cpSync(join(platformDir, "config.xml"), join(outDir, "config.xml"));
    const iconSrc = join(platformDir, "icon.png");
    if (!existsSync(iconSrc)) {
      console.error(
        `Missing platforms/${platformName}/icon.png (required by config.xml). Add a 512x512 PNG before packaging.`,
      );
      process.exit(1);
    }
    cpSync(iconSrc, join(outDir, "icon.png"));
    return;
  }

  cpSync(join(root, "platforms/webos/appinfo.json"), join(outDir, "appinfo.json"));
  for (const name of ["icon.png", "largeIcon.png"]) {
    const src = join(root, "platforms/webos", name);
    if (!existsSync(src)) {
      console.error(
        `Missing platforms/webos/${name} (required by appinfo.json). Add the asset before packaging.`,
      );
      process.exit(1);
    }
    cpSync(src, join(outDir, name));
  }
}

if (platform === "tizen-legacy") {
  console.log("Building Tizen legacy (5.5 / Chrome 69) bundle…");
  run(isWindows ? "npm.cmd" : "npm", ["run", "build:tizen-legacy:web"]);
  const webOut = join(root, "dist-tizen-legacy-web");
  if (!existsSync(webOut)) {
    console.error("Missing dist-tizen-legacy-web/ after legacy build");
    process.exit(1);
  }
  const outDir = join(root, "dist-tizen-legacy");
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });
  cpSync(webOut, outDir, { recursive: true });
  copyPlatformAssets("tizen-legacy", outDir);
  pruneLegacyFonts(outDir);
  console.log(`Packaging stub ready in ${outDir}/`);
  process.exit(0);
}

console.log("Building web bundle…");
run(isWindows ? "npm.cmd" : "npm", ["run", "build"]);

const dist = join(root, "dist");
if (!existsSync(dist)) {
  console.error("Missing dist/ after build");
  process.exit(1);
}

if (platform === "web") {
  console.log("Web build ready in dist/");
  process.exit(0);
}

const outDir = join(root, platform === "tizen" ? "dist-tizen" : "dist-webos");
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });
cpSync(dist, outDir, { recursive: true });
copyPlatformAssets(platform, outDir);
pruneLegacyFonts(outDir);

console.log(`Packaging stub ready in ${outDir}/`);
