#!/usr/bin/env node
/**
 * Sign a Tizen dist directory into a TV-installable .wgt using the Tizen Studio CLI.
 *
 * Requires:
 *   - `tizen` on PATH (Tizen Studio → tools/ide/bin)
 *   - A Certificate Manager security profile (Samsung cert for real TVs)
 *
 * Env:
 *   TIZEN_SECURITY_PROFILE  Profile name (required)
 *   TIZEN_DIST_DIR           Dist folder relative to repo root (default dist-tizen)
 *   TIZEN_PROFILES_PATH      Optional path to profiles.xml (cli-config)
 *   TIZEN_SIGNED_OUT         Optional output .wgt path
 *
 * Usage:
 *   npm run build:tizen
 *   TIZEN_SECURITY_PROFILE=PrairieDev npm run sign:tizen
 *   TIZEN_DIST_DIR=dist-tizen-legacy TIZEN_SECURITY_PROFILE=PrairieDev npm run sign:tizen
 */
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const isWindows = process.platform === "win32";
const distRel = (process.env.TIZEN_DIST_DIR ?? "dist-tizen").trim() || "dist-tizen";
const source = join(root, distRel);
const artifacts = join(root, "artifacts");
const profile = (process.env.TIZEN_SECURITY_PROFILE ?? "").trim();
const profilesPath = (process.env.TIZEN_PROFILES_PATH ?? "").trim();
const isLegacy = distRel.includes("legacy");

function run(command, args, opts = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: "inherit",
    shell: isWindows,
    ...opts,
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
  return result;
}

function commandExists(name) {
  const probe = spawnSync(isWindows ? "where" : "which", [name], { encoding: "utf8" });
  return probe.status === 0;
}

if (!profile) {
  console.error("Set TIZEN_SECURITY_PROFILE to your Certificate Manager profile name.");
  process.exit(1);
}

if (!commandExists("tizen")) {
  console.error("Tizen CLI (`tizen`) not found on PATH.");
  console.error("Install Tizen Studio + TV extensions, then add tools/ide/bin to PATH.");
  process.exit(1);
}

if (!existsSync(join(source, "config.xml")) || !existsSync(join(source, "index.html"))) {
  console.error(
    `${distRel}/ is missing. Run \`npm run build:${isLegacy ? "tizen-legacy" : "tizen"}\` first.`,
  );
  process.exit(1);
}

if (profilesPath) {
  if (!existsSync(profilesPath)) {
    console.error(`TIZEN_PROFILES_PATH not found: ${profilesPath}`);
    process.exit(1);
  }
  run("tizen", ["cli-config", "-g", `default.profiles.path=${profilesPath}`]);
}

const before = new Set(
  readdirSync(source)
    .filter((name) => name.endsWith(".wgt"))
    .map((name) => join(source, name)),
);

console.log(`Signing ${distRel}/ with profile "${profile}"…`);
run("tizen", ["package", "-t", "wgt", "-s", profile, "--", source]);

const after = readdirSync(source)
  .filter((name) => name.endsWith(".wgt"))
  .map((name) => join(source, name));
const created = after.filter((path) => !before.has(path));
const signedSource =
  created[0] ?? after.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs)[0];

if (!signedSource || !existsSync(signedSource)) {
  console.error(`tizen package finished but no .wgt was found under ${distRel}/.`);
  process.exit(1);
}

const version = JSON.parse(readFileSync(join(root, "package.json"), "utf8")).version || "0.0.0";
mkdirSync(artifacts, { recursive: true });
const defaultName = isLegacy
  ? `Prairie-${version}-tizen-legacy.wgt`
  : `Prairie-${version}-tizen.wgt`;
const out = (process.env.TIZEN_SIGNED_OUT ?? "").trim() || join(artifacts, defaultName);
if (existsSync(out)) rmSync(out);
renameSync(signedSource, out);
console.log(`Wrote signed package ${out} (${statSync(out).size} bytes)`);
console.log("Install on a developer-mode TV (DUID registered to this profile):");
console.log(`  tizen install -n ${out.split(/[/\\\\]/).pop()} -- ${artifacts}`);
