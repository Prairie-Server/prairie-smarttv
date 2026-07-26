#!/usr/bin/env node
/**
 * Stamp a semver into package.json, platforms/tizen/config.xml, and
 * platforms/webos/appinfo.json so release tags cannot drift across manifests.
 *
 * Usage: node scripts/stamp-version.mjs 1.2.3
 */
import { renameSync, writeFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const version = (process.argv[2] ?? "").trim();

if (!/^\d+\.\d+\.\d+([.-][0-9A-Za-z.-]+)?$/.test(version)) {
  console.error(`Invalid version "${version}". Expected semver like 1.2.3`);
  process.exit(1);
}

function writeAtomic(path, contents) {
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, contents);
  renameSync(tmp, path);
}

const pkgPath = join(root, "package.json");
const configPath = join(root, "platforms/tizen/config.xml");
const appinfoPath = join(root, "platforms/webos/appinfo.json");

const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
const config = readFileSync(configPath, "utf8");
const appinfo = JSON.parse(readFileSync(appinfoPath, "utf8"));

const nextConfig = config.replace(/(<widget\b[^>]*\bversion=")([^"]+)(")/, `$1${version}$3`);
if (nextConfig === config && !config.includes(`version="${version}"`)) {
  console.error("Failed to update version attribute in platforms/tizen/config.xml");
  process.exit(1);
}

pkg.version = version;
appinfo.version = version;

const nextPkg = `${JSON.stringify(pkg, null, 2)}\n`;
const nextAppinfo = `${JSON.stringify(appinfo, null, 2)}\n`;

writeAtomic(pkgPath, nextPkg);
writeAtomic(configPath, nextConfig);
writeAtomic(appinfoPath, nextAppinfo);

console.log(`Stamped version ${version} into package.json, config.xml, and appinfo.json`);
