#!/usr/bin/env node
import { cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");

const args = process.argv.slice(2);
const platformFlag = args.find((a) => a === "tizen" || a === "webos")
  ?? args[args.indexOf("--platform") + 1];
const platform = platformFlag === "tizen" || platformFlag === "webos" ? platformFlag : "web";

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, { cwd: root, stdio: "inherit", shell: false });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

console.log("Building web bundle…");
run("npm", ["run", "build"]);

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
  for (const name of ["icon.png", "largeIcon.png"]) {
    const src = join(root, "platforms/webos", name);
    if (existsSync(src)) cpSync(src, join(outDir, name));
  }
  if (!existsSync(join(outDir, "icon.png"))) {
    writeFileSync(
      join(outDir, "ICON_PLACEHOLDER.txt"),
      "Add platforms/webos/icon.png and largeIcon.png before packaging.\n",
    );
  }
}

console.log(`Packaging stub ready in ${outDir}/`);
