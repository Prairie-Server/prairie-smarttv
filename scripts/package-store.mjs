#!/usr/bin/env node
/**
 * Build store-ready (or signing-ready) packages for Tizen (.wgt) and webOS (.ipk).
 *
 * - Tizen: zips dist-tizen/ into artifacts/Prairie-<version>-tizen-unsigned.wgt
 *   (a .wgt is a zip). Sign with Tizen CLI / Certificate Manager before Seller Office.
 * - webOS: prefers `ares-package` when installed; otherwise writes an unsigned
 *   zip of dist-webos/ and prints the ares-package command for store signing.
 */
import { existsSync, mkdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const isWindows = process.platform === "win32";

const args = process.argv.slice(2);
const platformArg = args.find((a) => a === "tizen" || a === "webos" || a === "all") ?? "all";

function run(command, commandArgs, opts = {}) {
  const result = spawnSync(command, commandArgs, {
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

function readVersion() {
  const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
  return pkg.version || "0.0.0";
}

function zipDirectory(sourceDir, outFile) {
  if (existsSync(outFile)) rmSync(outFile);
  mkdirSync(dirname(outFile), { recursive: true });

  if (commandExists("zip")) {
    run("zip", ["-r", "-q", outFile, "."], { cwd: sourceDir });
    return;
  }

  if (commandExists("python3")) {
    const script = `
import pathlib, sys, zipfile
src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for path in src.rglob("*"):
        if path.is_file():
            zf.write(path, path.relative_to(src).as_posix())
`;
    const result = spawnSync("python3", ["-c", script, sourceDir, outFile], {
      cwd: root,
      stdio: "inherit",
    });
    if (result.status !== 0) process.exit(result.status ?? 1);
    return;
  }

  console.error("Need `zip` or `python3` on PATH to create store packages.");
  process.exit(1);
}

function packageTizen(version) {
  console.log("Building Tizen bundle…");
  run(isWindows ? "npm.cmd" : "npm", ["run", "build:tizen"]);
  const source = join(root, "dist-tizen");
  const artifacts = join(root, "artifacts");
  mkdirSync(artifacts, { recursive: true });
  const out = join(artifacts, `Prairie-${version}-tizen-unsigned.wgt`);
  zipDirectory(source, out);
  console.log(`Wrote ${out} (${statSync(out).size} bytes)`);
  console.log("Sign before Samsung Seller Office upload:");
  console.log(`  tizen package -t wgt -s <distributor-profile> -- ${source}`);
  console.log("  # or Package with Certificate Manager in Tizen Studio");
}

function packageWebos(version) {
  console.log("Building webOS bundle…");
  run(isWindows ? "npm.cmd" : "npm", ["run", "build:webos"]);
  const source = join(root, "dist-webos");
  const artifacts = join(root, "artifacts");
  mkdirSync(artifacts, { recursive: true });

  if (commandExists("ares-package")) {
    run("ares-package", [source, "-o", artifacts]);
    console.log("ares-package completed. Sign/submit with your LG Developer Partner tools.");
    return;
  }

  const out = join(artifacts, `Prairie-${version}-webos-unsigned.zip`);
  zipDirectory(source, out);
  console.log(`ares-package not found — wrote staging zip ${out}`);
  console.log("Install @webos-tools/cli, then create a real .ipk:");
  console.log(`  ares-package ${source} -o artifacts`);
  console.log("Sign with your LG Developer Partner certificate before LG Content Store upload.");
}

const version = readVersion();

if (platformArg === "tizen" || platformArg === "all") {
  packageTizen(version);
}
if (platformArg === "webos" || platformArg === "all") {
  packageWebos(version);
}
