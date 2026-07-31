# Prairie SmartTV — Flutter rewrite

Flutter rewrite of the Tizen and webOS TV apps. This is the only Smart TV client
tree — the former TypeScript/React app under `src/` has been removed.

## Layout

```
flutter/
  packages/
    pubspec.yaml     # pub workspace root (prairie_webos + flutter_secure_storage_webos)
    prairie_core/    # shared Dart: routing, models, performance-tier, VideoBackend
    prairie_tizen/   # Samsung Tizen app (flutter-tizen) + AVPlay backend
    prairie_webos/   # LG webOS app (flutter-webos) + video_player_drm backend
    flutter_secure_storage_webos/  # path fork: platform_interface ^2 for secure storage
  scripts/
    stamp-tizen-package-version.sh   # stamp the release version into tizen-manifest.xml
    build-tizen.sh                   # build the Tizen TPK
    build-webos.sh                   # build webOS .ipk
    validate-package-layout.sh       # CI-friendly layout/manifest checks (no SDKs)
  artifacts/                         # local build outputs (gitignored)
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

Install **Tizen Studio** (real CLI install, not the VS Code extension SDK — Samsung has since
deprecated Tizen Studio itself in favor of the VS Code extension as of 6.1, but this app's local
dev + CI toolchain both still use classic Tizen Studio, which continues to work), the TV
Extension, and a Samsung distributor certificate. Then `flutter-tizen doctor -v` until the
toolchain check passes. Details: https://github.com/flutter-tizen/flutter-tizen

#### Why only one Tizen api-version / TPK

The checked-in manifest's `api-version="6.5"` spans Tizen OS 6.5–9.0+ in a single TPK. This app
used to ship three Store variants (6.0 / 6.5 / 10.0) because `video_player_avplay` packages
**api-version-specific** precompiled native libraries — one TPK could not span all Tizen OS
versions with that plugin. This app now uses `video_player_videohole` instead (switched to avoid
`video_player_avplay`'s GStreamer HLS demux hard-linking `libclearkey.so.0`, which Smack blocks on
a retail signing cert — see git history), which compiles from source with no such split, so the
multi-variant stamping/build machinery was removed.

```bash
./flutter/scripts/build-tizen.sh --package-version 1.0.1
./flutter/scripts/build-tizen.sh --package-version 1.0.1 --security-profile Prairie_Server --obfuscate
```

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

# webOS app + secure_storage path fork share a pub workspace:
cd ../..   # flutter/packages
flutter pub get
flutter analyze prairie_webos flutter_secure_storage_webos

# Tizen (Dart analyze only without TV SDKs):
cd prairie_tizen && flutter pub get && flutter analyze

# Manifest / variant layout (no SDKs required):
bash flutter/scripts/validate-package-layout.sh
```

## Building & deploying

### Tizen TV

1. Developer Mode on the TV → set Host PC IP → reboot if prompted.
2. `sdb connect <tv-ip>`
3. `cd flutter/packages/prairie_tizen && flutter-tizen build tpk --device-profile tv`
4. `flutter-tizen -d <tv-ip>:26101 install && flutter-tizen -d <tv-ip>:26101 run --release`

Or use `./flutter/scripts/build-tizen.sh` (`--package-version`/`--security-profile`/`--obfuscate`
optional).

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

## CI

`release-packages.yml` installs both TV toolchains from scratch on GitHub-hosted `ubuntu-22.04`
runners (Tizen SDK 10.0 + NativeCLI/toolchain for the `.tpk`; the official LG
`lg-flutter-webos/ndk` + `flutter-webos` for the `.ipk`). No self-hosted runner, no persistent
infra, and **no signing secrets** — the Tizen build is signed with a fresh CI author certificate
under gnome-keyring, which makes the `.tpk` installable in TV Developer Mode but not
Store-signed. Re-sign with your real distributor certificate at actual install time — e.g.
[Apps2Samsung](https://apps2samsung.com/) accepts a "bring your own package" `.tpk`/`.wgt` and
re-signs it during install — or Tizen Studio's Certificate Manager.

| Workflow | Does |
| --- | --- |
| `unit-tests.yml` | analyze + test `prairie_core`; Dart analyze platform pkgs; layout validation |
| `release-packages.yml` | same verify gate, then real `.tpk` / `.ipk` builds, attached to the GitHub Release on a `v*` tag push |
