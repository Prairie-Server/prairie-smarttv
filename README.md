# Prairie Smart TV

AGPL-3.0 client for **Samsung Tizen** and **LG webOS**, sharing one remote-first web app that talks to Prairie over native `/api/v1` (not Jellyfin-primary).

Prairie Dusk UI: deep slate `#141820`, amber `#e0a84a`, Sora + Fraunces.

## What’s included

- Connect to a Prairie server (username / password)
- **Profile picker** (PIN unlock when required)
- **Home** rails from `/api/v1/home/sections` (continue watching, recently added, …)
- **Libraries** browse with pagination (`/api/v1/user/libraries` + `/api/v1/catalog`)
- **Collections** (library + personal) → catalog items
- **Search** across the catalog
- **Item detail** → seasons/episodes for series → Play via `/api/v1/watch/{id}` + `/playback/start`
- Playback backends: HTML5 / Tizen AVPlay / webOS Starfish-style
- Troubleshooting settings: force direct / force transcode, backend preference

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

| Command | Purpose |
| --- | --- |
| `npm run dev` | Vite dev server |
| `npm run build` | Typecheck + production web bundle → `dist/` |
| `npm test` | Vitest unit tests |
| `npm run test:coverage` | Vitest + coverage gate (75% on core modules) |
| `npm run build:web` | Same as production web build |
| `npm run build:tizen` | Web build + copy into `dist-tizen/` with `config.xml` |
| `npm run build:webos` | Web build + copy into `dist-webos/` with `appinfo.json` |

Packaging into `.wgt` / `.ipk` still needs Tizen Studio / ares-cli — see `platforms/tizen/` and `platforms/webos/`.

## Coverage CI

GitHub Actions runs `npm run test:coverage`. Vitest thresholds (**75%** statements/lines/functions, **70%** branches) apply to:

- `src/api/client.ts`
- `src/api/playback.ts`
- `src/api/watch.ts`
- `src/settings/playbackSettings.ts`
- `src/player/createPlayer.ts`

UI screens and native AVPlay/Starfish adapters are excluded until they have unit tests.

## Player backends

| Backend | When |
| --- | --- |
| **HTML5** | Dev browser, explicit setting, or fallback |
| **AVPlay** | Samsung Tizen native (`webapis.avplay`) |
| **Starfish-style** | LG webOS HTML5 `<video>` with `mediaOption` / `mediaPreferred` hints |

On the player screen: **OK / Enter** toggles play-pause; **Back / Escape** exits and destroys the native player instance.

## API surface

1. `POST /api/v1/auth/login`
2. `GET /api/v1/profiles` (+ `POST …/verify-pin` when needed)
3. `GET /api/v1/home/sections`
4. `GET /api/v1/user/libraries` · `GET /api/v1/catalog`
5. `GET /api/v1/library/{id}/collections` · `GET /api/v1/collections`
6. `GET /api/v1/catalog/items/{id}` · seasons/episodes · `GET /api/v1/watch/{id}`
7. `POST /api/v1/playback/start` → play `stream_url`

Session auth is in `localStorage` (`prairie.session`): server URL, tokens, active profile id / PIN token.

## Layout

```text
src/
  api/           Prairie /api/v1 client, auth, catalog, home, watch, playback
  platform/      detect + tizen/avplay + webos/starfish adapters
  player/        backend selection, HTML5 host, PlayerHost
  settings/      playback troubleshooting settings + screen
  screens/       Connect, profiles, home/libraries/collections/search/detail/player
  components/    Shell nav, poster cards, media rows
platforms/       Tizen config.xml + webOS appinfo.json stubs
```

## Still follow-up

Richer player chrome (seek, audio/subs), Live TV, For You recommendations polish, spatial focus engine, and signed store packages.

## License

GNU Affero General Public License v3.0 (or later) — see [LICENSE](./LICENSE).

This project does **not** copy Moonfin, Enact, or other proprietary TV client source. Player adapters are thin wrappers over documented platform APIs.
