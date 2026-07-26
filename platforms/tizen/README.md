# Tizen packaging (1.0)

## Supported Tizen versions

Prairie ships **two** Tizen packages (Moonfin/Litefin-style). Install `required_version` is kept at **2.3** (same as Litefin) so Apps2Samsung **Public** certificates work. Which build you pick is about the TV’s WebKit engine, not the install floor:

| Package id   | App name     | Build target                        | Use on                         | Artifact                      |
| ------------ | ------------ | ----------------------------------- | ------------------------------ | ----------------------------- |
| `PrairieApp` | Prairie      | Vite `es2019` + native ES modules   | Tizen 6.0+ (6.5 / 7 / 8, …)    | `Prairie-*-tizen*.wgt`        |
| `PrairieLte` | Prairie Lite | `@vitejs/plugin-legacy` → Chrome 69 | Older WebKits (~Tizen 5.5 era) | `Prairie-*-tizen-legacy*.wgt` |

Your Tizen **6.5** TV should use the **modern** package.

## Build unsigned `.wgt` (CI staging)

```bash
npm run package:tizen          # modern
npm run package:tizen-legacy   # legacy
npm run package:store          # modern + legacy + webOS
```

Writes under `artifacts/`:

- `Prairie-<version>-tizen-unsigned.wgt`
- `Prairie-<version>-tizen-legacy-unsigned.wgt`

An unsigned `.wgt` is a zip of the dist folder. TVs will not install it **as-is** — something has to sign it first. For most users that “something” is Apps2Samsung (below), not our CI secrets.

## Distribution paths (pick one)

| Path                                | Who can install                                             | What we ship                                                        | Developer Mode? |
| ----------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------- | --------------- |
| **Apps2Samsung / custom `.wgt`**    | Anyone (each person signs for _their_ TV)                   | **Unsigned** `*-tizen-unsigned.wgt` / `*-tizen-legacy-unsigned.wgt` | Yes             |
| **Your CI / local Samsung cert**    | Only TVs whose **DUID** is on _your_ distributor cert (≤50) | Signed `*-tizen.wgt` via `TIZEN_*` secrets                          | Yes             |
| **Samsung Apps TV (Seller Office)** | Everyone via the store (no sideload)                        | Signed package you upload; Samsung re-signs for the store           | No              |

### Apps2Samsung (recommended for “everyone” sideload)

[Apps2Samsung](https://apps2samsung.com/) downloads a community/custom `.wgt`, creates a **Samsung developer certificate for that user’s TV**, re-signs, and installs. So:

- **Do not** rely on our DUID-locked CI secrets for public installs — those only unlock _your_ TVs.
- **Do** publish the **unsigned** release artifacts (already produced by CI).
- End users: Developer Mode on → Apps2Samsung → Custom WGT (or catalog entry) → install with the default **Public** cert (Partner signing is **not** required for Prairie).

Package ids are 10-character alphanumeric (`PrairieApp` / `PrairieLte`) and `required_version` is `2.3`, matching Litefin/Moonfin so installs behave like the Apps2Samsung catalog apps. Apps2Samsung only auto-bumps to Partner for packages that declare `vpnservice` (e.g. Tailscale) — Prairie does not.

If you previously installed an older Prairie build (`package="prairie"`), uninstall it first — the package id changed.

Catalog listing (optional): add a provider in Apps2Samsung’s [`third-party-apps.json`](https://github.com/Apps2Samsung/Apps2Samsung/blob/main/third-party-apps.json) pointing at `https://api.github.com/repos/Prairie-Server/prairie-smarttv/releases` (same pattern as Moonfin/Litefin). Until then, users can load the GitHub Release `.wgt` via **Custom WGT/TPK**.

### Samsung Seller Office (real store)

For install **without** Developer Mode / Apps2Samsung: register in [TV Seller Office](https://seller.samsungapps.com/), upload a package signed with your Samsung author certificate, pass Samsung verification. On acceptance, Samsung swaps in the store distributor certificate so any supported TV can install from Apps. That is a separate product/process from GitHub Releases.

## Sign locally / CI (your TVs only)

Samsung TVs only install packages signed with a **Samsung Certificate Manager** profile. A distributor cert with your DUID list is a **personal** cert — not a public one:

1. Install [Tizen Studio](https://developer.tizen.org/development/tizen-studio) + **TV Extensions** + **Samsung Certificate Extension**.
2. Enable **Developer Mode** on the TV and note the **DUID**.
3. In Certificate Manager, create a **Samsung** certificate profile and register that DUID (sideload).
4. Put Tizen Studio `tools/ide/bin` on your `PATH` so `tizen` works.
5. Build + sign:

```bash
npm run build:tizen
TIZEN_SECURITY_PROFILE=<YourProfileName> npm run sign:tizen

npm run build:tizen-legacy
TIZEN_DIST_DIR=dist-tizen-legacy TIZEN_SECURITY_PROFILE=<YourProfileName> npm run sign:tizen
```

Or auto-sign during package when the profile env var is set and `tizen` is on `PATH`:

```bash
TIZEN_SECURITY_PROFILE=<YourProfileName> npm run package:store
```

Install:

```bash
tizen install -n Prairie-<version>-tizen.wgt -- artifacts
# or Device Manager / sdb
```

Optional: `TIZEN_PROFILES_PATH=/path/to/profiles.xml` if the CLI cannot find Certificate Manager profiles.

## Generate GitHub signing secrets (maintainers’ TVs only)

Optional. These secrets produce signed release assets for **DUIDs on your distributor cert only**. Public Apps2Samsung users do **not** need them — they use the unsigned `.wgt` and sign locally via Apps2Samsung.

CI also signs when these repository secrets exist (Settings → Secrets and variables → Actions):

| Secret                       | Value                                      |
| ---------------------------- | ------------------------------------------ |
| `TIZEN_AUTHOR_P12`           | Base64 of `author.p12`                     |
| `TIZEN_AUTHOR_PASSWORD`      | Password you chose for the author cert     |
| `TIZEN_DISTRIBUTOR_P12`      | Base64 of `distributor.p12`                |
| `TIZEN_DISTRIBUTOR_PASSWORD` | Password for the distributor cert          |
| `TIZEN_SECURITY_PROFILE`     | Profile name (optional; default `Prairie`) |

### Step-by-step (Samsung — personal / CI cert)

Official guide: [Creating Certificates](https://developer.samsung.com/smarttv/develop/getting-started/setting-up-sdk/creating-certificates.html).

1. **Prereqs**
   - Samsung account on [Samsung Developers](https://developer.samsung.com/)
   - Tizen Studio with **Samsung Certificate Extension** + TV extensions

2. **Get your TV DUID**
   - On the TV: enable Developer Mode (Smart Hub → Apps → `12345` on remote → on → host PC IP)
   - DUID: **Support → Contact Samsung → Unique Device ID**, or from Tizen Studio **Device Manager** when the TV is connected
   - Connect the TV over the network (`sdb connect <tv-ip>`)

3. **Create a Samsung certificate profile**
   - Tizen Studio → **Tools → Certificate Manager** → **+**
   - Choose **Samsung** → **TV**
   - Name the profile (e.g. `Prairie`) — this becomes `TIZEN_SECURITY_PROFILE`
   - **Author certificate**: create new (or import existing `author.p12`). Set a password you will keep. Sign in with Samsung account. Back up the files.
   - **Distributor certificate**: create new. Privilege level **Public** is enough for Prairie (same as Litefin). Add your TV’s **DUID** (and any other test TVs, up to 50).
   - Finish

4. **Locate the `.p12` files**  
   Certificate Manager usually stores them under:

   - macOS / Linux: `~/SamsungCertificate/<ProfileName>/`
   - Windows: `C:\Users\<you>\SamsungCertificate\<ProfileName>\`

   You want:

   - `author.p12`
   - `distributor.p12` (sometimes named like `distributor.p12` / device distributor)

5. **Base64-encode for GitHub secrets**

   macOS / Linux:

   ```bash
   PROFILE_DIR="$HOME/SamsungCertificate/Prairie"   # your profile folder
   base64 -i "$PROFILE_DIR/author.p12" | tr -d '\n' > author.p12.b64
   base64 -i "$PROFILE_DIR/distributor.p12" | tr -d '\n' > distributor.p12.b64
   # On Linux GNU base64, use: base64 -w0 author.p12 > author.p12.b64
   ```

   Windows (PowerShell):

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\SamsungCertificate\Prairie\author.p12"))
   ```

6. **Add secrets** in the GitHub repo:
   - `TIZEN_AUTHOR_P12` ← contents of `author.p12.b64`
   - `TIZEN_AUTHOR_PASSWORD` ← author password (plain text)
   - `TIZEN_DISTRIBUTOR_P12` ← contents of `distributor.p12.b64`
   - `TIZEN_DISTRIBUTOR_PASSWORD` ← distributor password
   - `TIZEN_SECURITY_PROFILE` ← `Prairie` (or your profile name)

7. **Re-run Release packages** (or push a new `v*` tag). CI still always attaches **unsigned** `.wgt` files for Apps2Samsung; signed `Prairie-*-tizen.wgt` / `*-tizen-legacy.wgt` appear only when secrets are present.

**Important:** Keep the same author certificate for Seller Office updates. Losing it means you cannot update the same package id in the store. Back up `~/SamsungCertificate/` offline. Never commit `.p12` files to git.

Skip GitHub secrets entirely if you only care about Apps2Samsung / unsigned GitHub Releases.

## Privileges

Declared in `config.xml` (modern and legacy), aligned with Litefin/Moonfin Public installs:

- `http://tizen.org/privilege/internet`
- `http://tizen.org/privilege/tv.inputdevice`
- `http://tizen.org/privilege/download` — fetch remote `subtitle_urls` into `wgt-private-tmp`
- `http://tizen.org/privilege/filesystem.read`
- `http://developer.samsung.com/privilege/productinfo`
- `http://developer.samsung.com/privilege/network.public`
- `http://developer.samsung.com/privilege/avplay`

### AVPlay subtitles

Remote Prairie subtitle URLs are downloaded via the Tizen Download API, attached with
`setExternalSubtitlePath`, and rendered through `onsubtitlechange` into an HTML overlay so
Settings → Subtitles styling applies. `setSilentSubtitle(true)` turns captions off.

## Icons

`platforms/tizen/icon.png` is the Prairie 512×512 app icon. The build **fails** if it is missing.
Legacy uses `platforms/tizen-legacy/icon.png` (same asset by default).
