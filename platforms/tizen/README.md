# Tizen packaging (1.0)

## Supported Tizen versions

`config.xml` sets `required_version="6.0"`. **One package covers Tizen 6.0+** (6.0, 6.5, 7.0, 8.0, …), including Samsung TVs from roughly 2021 onward.

| TV generation (approx.) | Tizen | Supported?                             |
| ----------------------- | ----- | -------------------------------------- |
| 2021+                   | 6.0+  | Yes (single `.wgt`)                    |
| 2022 (e.g. many 6.5)    | 6.5   | Yes                                    |
| Newer                   | 7 / 8 | Yes                                    |
| 2020 and earlier        | 5.5   | **No** — needs a separate legacy build |

Prairie ships **one** Tizen web bundle (Vite `es2019` + ES modules + React 19). That is intentional — unlike Moonfin/Litefin-style dual clients, we do **not** maintain a second downlevel package for Tizen 5.5. Older WebKit cannot run this stack without a major fork.

Your Tizen **6.5** TV is in the supported range.

## Build unsigned `.wgt` (CI staging)

```bash
npm run package:tizen
```

Writes `artifacts/Prairie-<version>-tizen-unsigned.wgt`.

An unsigned `.wgt` is only a zip of `dist-tizen/`. **It will not install on a Samsung TV.** Use it as the input for signing, or sign in the same step (below).

## Sign so it installs (required for real TVs)

Samsung TVs only install packages signed with a **Samsung Certificate Manager** profile:

1. Install [Tizen Studio](https://developer.tizen.org/development/tizen-studio) + **TV Extensions**.
2. Enable **Developer Mode** on the TV and note the **DUID**.
3. In Certificate Manager, create a **Samsung** certificate profile and register that DUID (sideload / partner distributor).
4. Put Tizen Studio `tools/ide/bin` on your `PATH` so `tizen` works.
5. Build + sign:

```bash
npm run build:tizen
TIZEN_SECURITY_PROFILE=<YourProfileName> npm run sign:tizen
```

Or in one shot (auto-signs when the profile env var is set and `tizen` is on `PATH`):

```bash
TIZEN_SECURITY_PROFILE=<YourProfileName> npm run package:tizen
```

Output: `artifacts/Prairie-<version>-tizen.wgt`

Install:

```bash
tizen install -n Prairie-<version>-tizen.wgt -- artifacts
# or use Device Manager / sdb
```

Optional: `TIZEN_PROFILES_PATH=/path/to/profiles.xml` if the CLI cannot find Certificate Manager profiles.

### Seller Office (store) vs sideload

| Goal                    | Certificate                                            |
| ----------------------- | ------------------------------------------------------ |
| Sideload / your own TVs | Samsung certificate profile with each TV’s DUID        |
| Samsung Seller Office   | Seller Office author + Samsung-issued distributor cert |

Same `sign:tizen` command — switch active profile in Certificate Manager (or pass the store profile name).

### CI signed releases

The GitHub **Release packages** workflow always uploads the unsigned staging `.wgt`. If these repository secrets are set, it also installs the Tizen CLI, signs, and attaches `Prairie-<version>-tizen.wgt`:

| Secret                       | Purpose                                                      |
| ---------------------------- | ------------------------------------------------------------ |
| `TIZEN_AUTHOR_P12`           | Base64 of author `.p12`                                      |
| `TIZEN_AUTHOR_PASSWORD`      | Author key password                                          |
| `TIZEN_DISTRIBUTOR_P12`      | Base64 of distributor `.p12` (Samsung / device)              |
| `TIZEN_DISTRIBUTOR_PASSWORD` | Distributor key password                                     |
| `TIZEN_SECURITY_PROFILE`     | Profile name written into `profiles.xml` (default `Prairie`) |

Without those secrets, CI cannot invent certificates — sign locally as above.

## Privileges

Declared in `config.xml`:

- `http://tizen.org/privilege/internet`
- `http://tizen.org/privilege/tv.inputdevice`
- `http://tizen.org/privilege/download` — fetch remote `subtitle_urls` into `wgt-private-tmp`
- `http://tizen.org/privilege/filesystem.read`
- `http://developer.samsung.com/privilege/avplay`
- `http://developer.samsung.com/privilege/tvinfo` — in-app caption control

### AVPlay subtitles

Remote Prairie subtitle URLs are downloaded via the Tizen Download API, attached with
`setExternalSubtitlePath`, and rendered through `onsubtitlechange` into an HTML overlay so
Settings → Subtitles styling applies. `setSilentSubtitle(true)` turns captions off.

## Icons

`platforms/tizen/icon.png` is the Prairie 512×512 app icon. The build **fails** if it is missing.
