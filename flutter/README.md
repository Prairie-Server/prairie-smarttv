# Prairie SmartTV — Flutter rewrite

Flutter rewrite of the Tizen and webOS TV apps, replacing the TypeScript/React app in `../src`.
See `C:\Users\jonah\.claude\plans\should-we-consider-rewriting-abstract-lampson.md` for the full
rationale and plan. The TS app keeps shipping until this reaches cutover criteria — see the plan's
Migration/Rollout section.

## Layout

```
flutter/packages/
  prairie_core/    # shared Dart package: routing, models, performance-tier logic,
                    # VideoBackend interface. No native/platform code.
  prairie_tizen/    # Tizen app shell (flutter-tizen). Depends on prairie_core via a
                    # path dependency. Owns the AVPlay video backend and other
                    # Tizen-native platform code under lib/platform/.
  prairie_webos/    # (not yet started — see "webOS" below)
```

This split exists so each platform app only bundles the native code it actually needs, rather
than one binary carrying both Tizen and webOS native bridges.

## One-time environment setup

### Flutter SDK

```
git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter
```

Add `C:\src\flutter\bin` to `PATH`.

### flutter-tizen

```
git clone https://github.com/flutter-tizen/flutter-tizen.git C:\src\flutter-tizen
```

Add `C:\src\flutter-tizen\bin` to `PATH` (before or after the Flutter SDK path doesn't matter —
`flutter-tizen` wraps the Flutter SDK, it doesn't replace it). First run downloads its own pinned
Flutter engine — this is normal and separate from the `C:\src\flutter` checkout above.

### Tizen Studio

Do **not** rely on the Tizen VS Code extension's bundled SDK (`~/.tizen-extension-platform`) —
it's a stripped-down install with no real package repository and can't have missing packages
installed into it. Install the real Tizen Studio CLI instead:

1. Download the CLI installer from `https://download.tizen.org/sdk/Installer/tizen-studio_<version>/web-cli_Tizen_Studio_<version>_windows-64.exe` (check that URL for the current version — `tizen-studio_6.1` was current as of this writing).
2. Run it (requires admin elevation for the default `C:\tizen-studio` install path). Accept the license, use the default install path.
3. Set `TIZEN_SDK` to the install path so `flutter-tizen` uses it instead of any stray extension install:
   ```powershell
   [Environment]::SetEnvironmentVariable("TIZEN_SDK", "C:\tizen-studio", "User")
   ```
4. Run `C:\tizen-studio\package-manager\package-manager.exe` (admin) → **Extension SDK** tab → install
   **TV Extensions** (both 6.0 and 10.0 — see "Which Tizen platform version" below) and
   **Samsung Certificate Extension**.
5. Run `flutter-tizen doctor -v`. It will tell you the exact missing package command(s) to run, e.g.:
   ```
   C:\tizen-studio\package-manager\package-manager-cli.exe install IOT-Headed-6.0-NativeAppDevelopment-CLI
   ```
   Run whatever it asks for (also requires elevation) and re-run doctor until the Tizen toolchain
   check passes. (`package-manager-cli.exe` needs elevation for every invocation since it's
   installed under `C:\tizen-studio`, an admin-owned path — do the whole loop from one elevated
   terminal to avoid repeated UAC prompts.)

#### Which Tizen platform version?

Install **both** 6.0 and 10.0 platform packages: develop against 10.0 (current, required for
eventual Samsung Seller Office / App Store submission) while keeping the shipped app compatible
down to 6.0 (2021+ TV models — our supported floor, matching `flutter-tizen`'s own minimum).

#### GCC toolchain note

Samsung requires GCC 14.2.0-built binaries for 2026-model TVs specifically (GCC 9.2.0 covers
2021–2025 models) — this is a normal **multi-variant Store submission pattern** (ship separate
binaries per OS-version tier), not unique to Flutter. `flutter-tizen`'s own Dart/Flutter engine
build uses LLVM, not GCC — GCC only matters for native C/C++ plugin code. `flutter-tizen`
currently only supports GCC 9.2 ([upstream issue closed as "not planned"](https://github.com/flutter-tizen/flutter-tizen/issues/653)),
so **a 2026-TV-specific Store variant isn't buildable through this toolchain yet**. This covers
our 2021–2025 install base fine; it's a tracked, known gap for the newest hardware.

### Signing certificate (required for install/run, and for Apps2Samsung)

flutter-tizen needs an active Tizen security profile with a Samsung distributor certificate
(not just a plain Tizen one — Samsung devices specifically require the Samsung distributor cert,
which is also what makes Apps2Samsung sideload installs work).

1. Open `C:\tizen-studio\tools\certificate-manager` (no elevation needed — it writes to your user
   profile).
2. Create a new profile: Author certificate (any name/password), then add a **Samsung**
   certificate (this requires logging into your Samsung Developer account) as the distributor cert.
3. When prompted for a device list (DUID), get it from a real Samsung TV connected via `sdb`:
   ```
   C:\tizen-studio\tools\sdb.exe connect <tv-ip>
   ```
   Certificate Manager can auto-detect the DUID of a connected device rather than requiring manual
   entry — if the on-TV Developer Mode menu doesn't show the DUID directly (varies by model/year),
   connecting via `sdb` first and letting Certificate Manager pick it up is the more reliable path.
   Note `sdb shell` may be non-functional for arbitrary commands if `intershell_support` is
   disabled on the TV (check `sdb capability`) — this doesn't block Certificate Manager's own
   device detection, just ad-hoc shell commands.
4. Set the profile active:
   ```
   C:\tizen-studio\tools\ide\bin\tizen.bat security-profiles set-active -n <profile-name>
   ```
   (Certificate Manager also does this when you create/select a profile.)

## Running tests

```
cd flutter/packages/prairie_core   # or prairie_tizen
flutter analyze
flutter test
```

No coverage gate is wired into CI yet — see the plan's CI/Packaging section for the intended
`flutter test --coverage` + lcov threshold setup, to be added alongside the first real CI workflow.

## Building & deploying to a real Tizen TV

1. Put the TV in Developer Mode (Apps screen → button sequence **1 2 3 4 5** → enable Developer
   mode → set Host PC IP → reboot the TV if prompted) and note its IP address.
2. Connect:
   ```
   C:\tizen-studio\tools\sdb.exe connect <tv-ip>
   ```
3. Build, install, and run:
   ```
   cd flutter/packages/prairie_tizen
   flutter-tizen build tpk --device-profile tv
   flutter-tizen -d <tv-ip>:26101 install
   flutter-tizen -d <tv-ip>:26101 run --release
   ```
   (`flutter-tizen run` without `--release` gives hot reload during active development — prefer
   that day-to-day; use `--release` to validate what an actual signed release build behaves like.)

The signed `.tpk` lands at `build/tizen/tpk/org.prairieserver.prairie_tizen-<version>.tpk`. This
is the same file format and certificate chain Apps2Samsung expects for sideload distribution —
see the plan's cutover criteria for validating that distribution path end-to-end before relying
on it for real users.

## webOS

Not started yet in this package layout (`prairie_webos/` doesn't exist). Setup notes so far:

- `flutter-webos` (official LG SDK) only runs on Linux — use WSL2 Ubuntu on Windows.
- Requires Node 14.15.1–16.20.2 specifically for the `@webos-tools/cli` (`ares`) — use `nvm`,
  don't touch system Node. **Gotcha**: WSL inherits Windows' PATH by default, which can shadow the
  nvm-installed `node`/`ares` — make sure nvm's bin directory wins, and be careful with
  `.bashrc` edits from a non-interactive shell: variable expansion inside a `cat >> ~/.bashrc <<
  "EOF"` heredoc can silently bake in a stale absolute `PATH` snapshot instead of staying dynamic.
  Verify what actually landed in `.bashrc` after any scripted edit.
- Needs the webOS NDK (`webos-ndk-flutter-starfish-x86_64-*.sh` installer) and `WEBOS_FLUTTER_NDK_ENV`
  pointed at its `environment-setup-*` script.
- **We don't own an LG TV** — testing/development will need the webOS TV emulator once this
  resumes.
