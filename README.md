# Prairie Smart TV

AGPL-3.0 client for **Samsung Tizen** and **LG webOS**, sharing one remote-first web app that talks to Prairie over native `/api/v1` (not Jellyfin-primary).

**Version 1.0.0** — Prairie Dusk UI: deep slate `#141820`, amber `#e0a84a`, Sora + Fraunces.

## What’s included

- Connect to a Prairie server (username / password)
- **Multi-server registry** + **LAN discovery** (`GET /api/v1/health` probes; Scan LAN / Servers)
- **Profile picker** (PIN unlock when required)
- **Home** rails from `/api/v1/home/sections`
- **Libraries** browse with pagination (`/api/v1/user/libraries` + `/api/v1/catalog`)
- **Collections** (library + personal) → catalog items
- **Search** across the catalog
- **Live TV** channel list + guide now/next (tab hidden when the server has no enabled channels)
- **Item detail** → seasons/episodes → Play via `/api/v1/watch/{id}` + `/playback/start` with resume
- **Player chrome**: play/pause, ±15s seek, scrub readout, progress reporting, audio track switch, client-side subtitle selection, session teardown on exit
- **Subtitle styling**: size, text/background color, opacity, box/shadow/outline, position (persisted; HTML5/webOS `::cue` + Tizen AVPlay overlay)
- **Upgrade-safe persistence**: session + settings + last server URL survive app updates; logout keeps last server URL for reconnect
- Spatial D-pad focus (geometry-based, not DOM-order)
- Playback backends: HTML5 / Tizen AVPlay / webOS Starfish-style
- Troubleshooting settings: force direct / force transcode, backend preference
- Store packaging scripts for unsigned `.wgt` / `.ipk` staging + signing docs

## Requirements

- Node.js 20+ (22 recommended)
- A reachable Prairie server

## Quick start

```bash
npm install
npm run dev
```

Open the printed local URL (default `http://localhost:5174`). On a TV emulator/device, point the web app at your Prairie server URL.

Optional default server for the connect form:

```bash
VITE_DEFAULT_SERVER_URL=https://prairie.example.com npm run dev
```

## Scripts

| Command                        | Purpose                                                         |
| ------------------------------ | --------------------------------------------------------------- |
| `npm run dev`                  | Vite dev server                                                 |
| `npm run build`                | Typecheck + production web bundle → `dist/`                     |
| `npm run lint`                 | Oxlint (type-aware TypeScript + React Hooks via tsgolint/TS7)   |
| `npm run format`               | Prettier write                                                  |
| `npm run format:check`         | Prettier check (CI)                                             |
| `npm run typecheck`            | `tsc --noEmit`                                                  |
| `npm test`                     | Vitest unit tests                                               |
| `npm run test:coverage`        | Vitest + **75%** coverage gate on logic modules                 |
| `npm run build:web`            | Same as production web build                                    |
| `npm run build:tizen`          | Web build + copy into `dist-tizen/` with `config.xml`           |
| `npm run build:tizen-legacy`   | Chrome 69 downlevel build → `dist-tizen-legacy/` (Prairie Lite) |
| `npm run build:webos`          | Web build + copy into `dist-webos/` with `appinfo.json`         |
| `npm run package:tizen`        | Modern 6.0+ unsigned `.wgt` (auto-signs if profile set)         |
| `npm run package:tizen-legacy` | Legacy 5.5+ Prairie Lite `.wgt`                                 |
| `npm run sign:tizen`           | Sign `dist-tizen/` or `TIZEN_DIST_DIR=dist-tizen-legacy`        |
| `npm run package:webos`        | Build + `.ipk` (via ares) or staging zip under `artifacts/`     |
| `npm run package:store`        | Modern Tizen + legacy Tizen + webOS                             |

**Tizen targets:** dual packages — `PrairieApp` (modern es2019) and `PrairieLte` (Chrome 69 legacy). Install floor `required_version="2.3"` like Litefin so Apps2Samsung **Public** certs work. Details: `platforms/tizen/README.md`.

**Public sideload (Apps2Samsung):** ship the **unsigned** `*-tizen-unsigned.wgt` / `*-tizen-legacy-unsigned.wgt` from GitHub Releases. Apps2Samsung re-signs with each user’s **Public** Samsung cert (Partner not required). DUID-locked CI secrets only unlock _your_ TVs. Store listing without Developer Mode is Samsung Seller Office (separate process).

### GitHub Release packages

Push a `v*` tag (or run **Release packages** via `workflow_dispatch`) to build CI artifacts:

- Unsigned Tizen `.wgt` (`Prairie-<version>-tizen-unsigned.wgt`)
- Unsigned Tizen legacy `.wgt` (`Prairie-<version>-tizen-legacy-unsigned.wgt`)
- Signed Tizen `.wgt` files when `TIZEN_*` repo secrets are configured
- webOS `.ipk` via `@webos-tools/cli` (`ares-package`)

Workflow: `.github/workflows/release-packages.yml`. It stamps manifests from the tag version and uploads Actions artifacts. Tag runs also attach those files to a GitHub Release; manual `workflow_dispatch` runs build and upload artifacts only.

## Coverage CI

GitHub Actions runs lint, Prettier check, typecheck, build, then `npm run test:coverage`. Vitest thresholds are **75%** for statements, branches, functions, and lines on logic modules:

- `src/api/**`
- `src/storage/**`
- `src/focus/**`
- `src/settings/playbackSettings.ts`
- `src/player/createPlayer.ts`
- `src/player/createMediaPlayer.ts`
- `src/player/timeFormat.ts`
- `src/platform/detect.ts`

UI screens and native AVPlay/Starfish adapter implementations stay excluded (thin platform wrappers).

## Player backends

| Backend            | When                                                                 |
| ------------------ | -------------------------------------------------------------------- |
| **HTML5**          | Dev browser, explicit setting, or fallback                           |
| **AVPlay**         | Samsung Tizen native (`webapis.avplay`)                              |
| **Starfish-style** | LG webOS HTML5 `<video>` with `mediaOption` / `mediaPreferred` hints |

VOD player: **OK / Enter** toggles play-pause; **−15s / +15s** seek; Audio / Subs menus when tracks exist; **Back** reports progress, deletes the playback session, and destroys the native player.

Live TV uses `/api/v1/livetv/...` session start/release (not VOD `playback/start`).

## API surface

1. `POST /api/v1/auth/login`
2. `GET /api/v1/profiles` (+ `POST …/verify-pin` when needed)
3. `GET /api/v1/home/sections`
4. `GET /api/v1/user/libraries` · `GET /api/v1/catalog`
5. `GET /api/v1/library/{id}/collections` · `GET /api/v1/collections`
6. `GET /api/v1/catalog/items/{id}` · seasons/episodes · `GET /api/v1/watch/{id}`
7. `POST /api/v1/playback/start` → play `stream_url`
8. `POST /api/v1/playback/{id}/progress` · `PATCH …/audio` · `DELETE …/{id}`
9. `GET /api/v1/livetv/channels` · `GET …/guide` · `POST …/channels/{id}/session` · `DELETE …/sessions/{id}`

Session auth uses `sessionStorage` for tokens/profile PIN material and `localStorage` for non-secret identity like server URL and selected profile metadata.

## Layout

```text
src/
  api/           Prairie /api/v1 client, auth, health, catalog, home, watch, playback, livetv
  discovery/     LAN candidate builder + parallel /api/v1/health scan
  focus/         Spatial D-pad focus engine
  platform/      detect + tizen/avplay + webos/starfish adapters
  player/        backend selection, HTML5 host, PlayerHost, time helpers
  settings/      playback troubleshooting settings + screen
  storage/       session, server registry, upgrade-safe persistence
  screens/       Connect, server list, profiles, browse, Live TV, detail, player
  components/    Shell nav, poster cards, media rows
platforms/       Tizen config.xml + webOS appinfo.json + packaging docs
scripts/         build-web + package-store
```

## License

GNU Affero General Public License v3.0 (or later) — see [LICENSE](./LICENSE).

This project does **not** copy Moonfin, Enact, or other proprietary TV client source. Player adapters are thin wrappers over documented platform APIs.
