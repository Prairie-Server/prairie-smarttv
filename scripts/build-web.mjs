#!/usr/bin/env node
import { cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const isWindows = process.platform === "win32";
const ALLOWED_PLATFORMS = new Set(["web", "tizen", "webos"]);

const args = process.argv.slice(2);
const platformIdx = args.indexOf("--platform");
let platform = "web";

if (platformIdx !== -1) {
  const value = args[platformIdx + 1];
  if (!ALLOWED_PLATFORMS.has(value)) {
    console.error(
      `Invalid --platform "${value ?? ""}". Expected one of: web, tizen, webos.`,
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

if (platform === "tizen") {
  cpSync(join(root, "platforms/tizen/config.xml"), join(outDir, "config.xml"));
  const iconSrc = join(root, "platforms/tizen/icon.png");
  if (existsSync(iconSrc)) {
    cpSync(iconSrc, join(outDir, "icon.png"));
  } else {
    writeFileSync(
      join(outDir, "ICON_PLACEHOLDER.txt"),
      "Add platforms/tizen/icon.png (512x512) before packaging.\n",
    );
  }
} else {
  cpSync(join(root, "platforms/webos/appinfo.json"), join(outDir, "appinfo.json"));
  const missing = [];
  for (const name of ["icon.png", "largeIcon.png"]) {
    const src = join(root, "platforms/webos", name);
    if (existsSync(src)) {
      cpSync(src, join(outDir, name));
    } else {
      missing.push(name);
    }
  }
  if (missing.length > 0) {
    writeFileSync(
      join(outDir, "ICON_PLACEHOLDER.txt"),
      `Add platforms/webos/${missing.join(" and ")} before packaging.\n`,
    );
  }
}

console.log(`Packaging stub ready in ${outDir}/`);
