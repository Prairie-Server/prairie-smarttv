#!/usr/bin/env node
/**
 * Stamp a semver into package.json, Tizen config.xml (modern + legacy), and
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

function formatJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

/** Match oxfmt's preference for short arrays on one line (unit-tests gate). */
function formatAppinfoJson(value) {
  return formatJson(value).replace(
    /"requiredPermissions": \[\n(?:\s+"[^"]+",?\n)+?\s+\]/,
    (block) => {
      const items = [...block.matchAll(/"([^"]+)"/g)]
        .map((m) => m[1])
        .filter((name) => name !== "requiredPermissions");
      return `"requiredPermissions": [${items.map((name) => `"${name}"`).join(", ")}]`;
    },
  );
}

function stampConfigXml(configPath) {
  const config = readFileSync(configPath, "utf8");
  const nextConfig = config.replace(/(<widget\b[^>]*\bversion=")([^"]+)(")/, `$1${version}$3`);
  if (nextConfig === config && !config.includes(`version="${version}"`)) {
    console.error(`Failed to update version attribute in ${configPath}`);
    process.exit(1);
  }
  return nextConfig;
}

const pkgPath = join(root, "package.json");
const tizenConfigPath = join(root, "platforms/tizen/config.xml");
const tizenLegacyConfigPath = join(root, "platforms/tizen-legacy/config.xml");
const appinfoPath = join(root, "platforms/webos/appinfo.json");

const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
const appinfo = JSON.parse(readFileSync(appinfoPath, "utf8"));
const nextTizenConfig = stampConfigXml(tizenConfigPath);
const nextTizenLegacyConfig = stampConfigXml(tizenLegacyConfigPath);

pkg.version = version;
appinfo.version = version;

writeAtomic(pkgPath, formatJson(pkg));
writeAtomic(tizenConfigPath, nextTizenConfig);
writeAtomic(tizenLegacyConfigPath, nextTizenLegacyConfig);
writeAtomic(appinfoPath, formatAppinfoJson(appinfo));

console.log(
  `Stamped version ${version} into package.json, tizen/config.xml, tizen-legacy/config.xml, and appinfo.json`,
);
