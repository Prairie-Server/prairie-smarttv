#!/usr/bin/env node
/**
 * Build store-ready (or signing-ready) packages for Tizen (.wgt) and webOS (.ipk).
 *
 * - Tizen modern: dist-tizen/ → Prairie-<version>-tizen-unsigned.wgt (6.0+)
 * - Tizen legacy: dist-tizen-legacy/ → Prairie-<version>-tizen-legacy-unsigned.wgt (5.5+)
 * - webOS: prefers `ares-package` when installed; otherwise staging zip
 *
 * Set TIZEN_SECURITY_PROFILE (+ tizen on PATH) to also produce signed .wgt files.
 */
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { deflateRawSync, crc32 } from "node:zlib";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const isWindows = process.platform === "win32";

const ALLOWED = new Set(["tizen", "tizen-legacy", "webos", "all"]);
const args = process.argv.slice(2);
const platformArg = args.find((a) => ALLOWED.has(a)) ?? "all";

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

function listFilesRecursive(dir) {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true, recursive: true })) {
    if (!entry.isFile()) continue;
    const absolute = join(entry.parentPath ?? entry.path, entry.name);
    // .wgt / .ipk entry names are always POSIX-separated, on every host OS.
    found.push({ absolute, name: relative(dir, absolute).split(sep).join("/") });
  }
  return found.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

/**
 * Write a ZIP (a .wgt is just a zip) with nothing but Node builtins.
 *
 * This used to shell out to `zip` or `python3`, neither of which exists on a
 * stock Windows box — packaging simply could not be verified locally there.
 * Entries are stored sorted with a fixed timestamp so repeat builds of the same
 * dist/ are byte-identical.
 */
function zipDirectory(sourceDir, outFile) {
  if (existsSync(outFile)) rmSync(outFile);
  mkdirSync(dirname(outFile), { recursive: true });

  const files = listFilesRecursive(sourceDir);
  const locals = [];
  const central = [];
  let offset = 0;

  for (const file of files) {
    const nameBytes = Buffer.from(file.name, "utf8");
    const contents = readFileSync(file.absolute);
    const deflated = deflateRawSync(contents, { level: 9 });
    // Never let "compression" grow an entry — fall back to stored.
    const useDeflate = deflated.length < contents.length;
    const payload = useDeflate ? deflated : contents;
    const method = useDeflate ? 8 : 0;
    const crc = crc32(contents);

    const localHeader = Buffer.alloc(30);
    localHeader.writeUInt32LE(0x04034b50, 0);
    localHeader.writeUInt16LE(20, 4); // version needed
    localHeader.writeUInt16LE(0x0800, 6); // UTF-8 names
    localHeader.writeUInt16LE(method, 8);
    localHeader.writeUInt16LE(0, 10); // mod time (fixed)
    localHeader.writeUInt16LE(0x0021, 12); // mod date (fixed: 1980-01-01)
    localHeader.writeUInt32LE(crc, 14);
    localHeader.writeUInt32LE(payload.length, 18);
    localHeader.writeUInt32LE(contents.length, 22);
    localHeader.writeUInt16LE(nameBytes.length, 26);
    localHeader.writeUInt16LE(0, 28); // extra field length
    locals.push(localHeader, nameBytes, payload);

    const centralHeader = Buffer.alloc(46);
    centralHeader.writeUInt32LE(0x02014b50, 0);
    centralHeader.writeUInt16LE(20, 4); // version made by
    centralHeader.writeUInt16LE(20, 6); // version needed
    centralHeader.writeUInt16LE(0x0800, 8);
    centralHeader.writeUInt16LE(method, 10);
    centralHeader.writeUInt16LE(0, 12);
    centralHeader.writeUInt16LE(0x0021, 14);
    centralHeader.writeUInt32LE(crc, 16);
    centralHeader.writeUInt32LE(payload.length, 20);
    centralHeader.writeUInt32LE(contents.length, 24);
    centralHeader.writeUInt16LE(nameBytes.length, 28);
    centralHeader.writeUInt16LE(0, 30); // extra
    centralHeader.writeUInt16LE(0, 32); // comment
    centralHeader.writeUInt16LE(0, 34); // disk number
    centralHeader.writeUInt16LE(0, 36); // internal attrs
    centralHeader.writeUInt32LE((0o100644 << 16) >>> 0, 38); // external attrs (regular file)
    centralHeader.writeUInt32LE(offset, 42);
    central.push(centralHeader, nameBytes);

    offset += localHeader.length + nameBytes.length + payload.length;
  }

  const centralBuffer = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(centralBuffer.length, 12);
  end.writeUInt32LE(offset, 16);

  writeFileSync(outFile, Buffer.concat([...locals, centralBuffer, end]));
}

function maybeSignTizen({ distDir, signedOut, buildHint }) {
  const profile = (process.env.TIZEN_SECURITY_PROFILE ?? "").trim();
  if (profile && commandExists("tizen")) {
    run(isWindows ? "npm.cmd" : "npm", ["run", "sign:tizen"], {
      env: {
        ...process.env,
        TIZEN_SECURITY_PROFILE: profile,
        TIZEN_DIST_DIR: distDir,
        TIZEN_SIGNED_OUT: signedOut,
      },
    });
    return;
  }

  console.log("Unsigned .wgt will not install on a Samsung TV.");
  console.log("Sign for sideload / Seller Office:");
  console.log(`  ${buildHint}`);
  console.log("  # requires Tizen Studio CLI + Certificate Manager profile");
}

function packageTizen(version) {
  console.log("Building Tizen (6.0+) bundle…");
  run(isWindows ? "npm.cmd" : "npm", ["run", "build:tizen"]);
  const source = join(root, "dist-tizen");
  const artifacts = join(root, "artifacts");
  mkdirSync(artifacts, { recursive: true });
  const out = join(artifacts, `Prairie-${version}-tizen-unsigned.wgt`);
  zipDirectory(source, out);
  console.log(`Wrote ${out} (${statSync(out).size} bytes)`);
  maybeSignTizen({
    distDir: "dist-tizen",
    signedOut: join(artifacts, `Prairie-${version}-tizen.wgt`),
    buildHint: "TIZEN_SECURITY_PROFILE=<profile> npm run sign:tizen",
  });
}

function packageTizenLegacy(version) {
  console.log("Building Tizen legacy (5.5+) bundle…");
  run(isWindows ? "npm.cmd" : "npm", ["run", "build:tizen-legacy"]);
  const source = join(root, "dist-tizen-legacy");
  const artifacts = join(root, "artifacts");
  mkdirSync(artifacts, { recursive: true });
  const out = join(artifacts, `Prairie-${version}-tizen-legacy-unsigned.wgt`);
  zipDirectory(source, out);
  console.log(`Wrote ${out} (${statSync(out).size} bytes)`);
  maybeSignTizen({
    distDir: "dist-tizen-legacy",
    signedOut: join(artifacts, `Prairie-${version}-tizen-legacy.wgt`),
    buildHint:
      "TIZEN_DIST_DIR=dist-tizen-legacy TIZEN_SECURITY_PROFILE=<profile> npm run sign:tizen",
  });
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
if (platformArg === "tizen-legacy" || platformArg === "all") {
  packageTizenLegacy(version);
}
if (platformArg === "webos" || platformArg === "all") {
  packageWebos(version);
}
