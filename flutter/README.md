# Prairie SmartTV — Flutter rewrite

Flutter rewrite of the Tizen and webOS TV apps, replacing the TypeScript/React app in `../src`.
The TS app keeps shipping until this reaches cutover criteria.

## Layout

```
flutter/
  packages/
    prairie_core/    # shared Dart: routing, models, performance-tier, VideoBackend
    prairie_tizen/   # Samsung Tizen app (flutter-tizen) + AVPlay backend
    prairie_webos/   # LG webOS app (flutter-webos) + video_player_drm backend
  scripts/
    stamp-tizen-api-version.sh   # stamp api-version for Store variants
    build-tizen.sh               # build one Tizen TPK variant
    build-webos.sh               # build webOS .ipk
    validate-package-layout.sh   # CI-friendly layout/manifest checks (no SDKs)
  artifacts/                     # local build outputs (gitignored)
```

Each platform app only bundles the native plugins it needs.

## One-time environment setup

### Flutter SDK

```bash
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
```

### flutter-tizen (Samsung)

```bash
git clone https://github.com/flutter-tizen/flutter-tizen.git ~/flutter-tizen
export PATH="$HOME/flutter-tizen/bin:$PATH"
```

Install **Tizen Studio** (real CLI install, not the VS Code extension SDK), TV Extensions
for **6.0 and 10.0**, and a Samsung distributor certificate. Then `flutter-tizen doctor -v`
until the toolchain check passes. Details: https://github.com/flutter-tizen/flutter-tizen

#### Which Tizen api-version? (three Store TPKs)

`video_player_avplay` packages **api-version-specific** native libraries. One TPK does **not**
span all Tizen OS versions. Ship three variants:

| `api-version` in `tizen-manifest.xml` | Covers Tizen OS |
| --- | --- |
| `6.0` | 6.0 only |
| `6.5` | 6.5–9.0 |
| `10.0` | 10.0 only |

The checked-in manifest defaults to **6.5** for day-to-day development. Stamp before release:

```bash
./flutter/scripts/stamp-tizen-api-version.sh 6.0
./flutter/scripts/build-tizen.sh 6.0
./flutter/scripts/build-tizen.sh 6.5 --package-version 1.0.1
./flutter/scripts/build-tizen.sh 10.0 --package-version 1.0.2 --obfuscate
```

See upstream:
https://github.com/flutter-tizen/plugins/blob/master/packages/video_player_avplay/README.md

#### GCC / 2026 TV note

Samsung wants GCC 14.2 for some 2026 models; `flutter-tizen` still targets GCC 9.2 for native
plugin code ([upstream #653](https://github.com/flutter-tizen/flutter-tizen/issues/653)).
2021–2025 panels are fine; newest hardware is a known gap.

### flutter-webos (LG)

`flutter-webos` is **Linux-only** (use WSL2 Ubuntu on Windows).

1. Install from https://github.com/lg-flutter-webos/flutter-webos and run `flutter-webos doctor`.
2. Install the webOS NDK and point `WEBOS_FLUTTER_NDK_ENV` at its `environment-setup-*` script.
3. Use **Node 14.15.1–16.20.2** for `@webos-tools/cli` (`ares`) via `nvm` — do not let a Windows
   PATH Node shadow the Linux one inside WSL.
4. Build:

```bash
./flutter/scripts/build-webos.sh --obfuscate
```

`appinfo.json` must keep `"transparent": true` so the hardware video plane shows through Flutter,
plus ACGs required by plugins (`systemconfig.query`, `securitykey.operation`).

## Running tests

```bash
cd flutter/packages/prairie_core
flutter analyze
flutter test

# Platform packages (Dart analyze only without TV SDKs):
cd ../prairie_tizen && flutter pub get && flutter analyze
cd ../prairie_webos && flutter pub get && flutter analyze

# Manifest / variant layout (no SDKs required):
bash flutter/scripts/validate-package-layout.sh
```

## Building & deploying

### Tizen TV

1. Developer Mode on the TV → set Host PC IP → reboot if prompted.
2. `sdb connect <tv-ip>`
3. `cd flutter/packages/prairie_tizen && flutter-tizen build tpk --device-profile tv`
4. `flutter-tizen -d <tv-ip>:26101 install && flutter-tizen -d <tv-ip>:26101 run --release`

Or use `./flutter/scripts/build-tizen.sh <api-version>` which stamps the manifest first.

### webOS TV / emulator

Use the webOS emulator if no physical LG TV is available. After `flutter-webos build`, package
with `ares-package` / install with `ares-install` as usual for native Flutter webOS apps.

## Package size notes

- **`uses-material-design: true`** is required while `prairie_core` uses `Icons.*`. Flutter
  tree-shakes Material Icons to used glyphs in release builds; replacing icons with a custom
  subset font later would shrink further.
- **`path_provider_tizen` / `path_provider_webos`** are omitted — unused by prairie_core.
- **Obfuscation**: pass `--obfuscate` to `build-tizen.sh` / `build-webos.sh` (forwards
  `--obfuscate --split-debug-info=...`). Keep the split debug info for crash symbolication.
- **Font subsetting**: `prairie_core` ships Sora + Fraunces as full TTFs. For smaller packages,
  subset to Latin + needed glyphs with `pyftsubset` / fontTools before release cutover, or switch
  to variable fonts with a unicode-range subset. Not automated in CI yet.

## CI limitations

GitHub `ubuntu-latest` runners do **not** include flutter-tizen or flutter-webos/NDK. Workflows:

| Workflow | Always | When SDKs present |
| --- | --- | --- |
| `unit-tests.yml` | analyze + test `prairie_core`; Dart analyze platform pkgs; layout validation | — |
| `release-packages.yml` | same verify gate; matrix for 4 artifacts | real `.tpk` / `.ipk` via build scripts |

Missing SDKs produce skip markers under `flutter/artifacts/*.SKIPPED.txt` instead of failing the
release job (unless `fail_without_sdk` is set on workflow_dispatch). Prefer a self-hosted runner
with the TV toolchains for Store binaries.
