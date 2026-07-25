# Prairie Smart TV

AGPL-3.0 client for **Samsung Tizen** and **LG webOS**, sharing one remote-first web app that talks to Prairie over native `/api/v1` (not Jellyfin-primary).

Prairie Dusk UI: deep slate `#141820`, amber `#e0a84a`, Sora + Fraunces.

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
| `npm run build:web` | Same as production web build |
| `npm run build:tizen` | Web build + copy into `dist-tizen/` with `config.xml` |
| `npm run build:webos` | Web build + copy into `dist-webos/` with `appinfo.json` |

Packaging into `.wgt` / `.ipk` still needs Tizen Studio / ares-cli and icons — see `platforms/tizen/` and `platforms/webos/`.

## Player backends

| Backend | When |
| --- | --- |
| **HTML5** | Dev browser, explicit setting, or fallback |
| **AVPlay** | Samsung Tizen native (`webapis.avplay`) |
| **Starfish-style** | LG webOS HTML5 `<video>` with `mediaOption` / `mediaPreferred` hints |

Selection is controlled in **Playback settings**:

- **Auto** — native on Tizen/webOS, HTML5 elsewhere
- **HTML5** — force the browser video element
- **Native** — AVPlay / Starfish-style (falls back to HTML5 if unavailable)

On the player screen: **OK / Enter** toggles play-pause; **Back / Escape** exits and destroys the native player instance.

## Troubleshooting playback settings

Stored in `localStorage` under `prairie.playbackSettings` (preferred over cookies on TV webviews):

- **Force Direct Play** → `play_method: "direct"` on `POST /api/v1/playback/start`
- **Force Transcode** → `play_method: "transcode"`
- Neither → omit `play_method` so Prairie can prefer remux / auto

Session auth is also in `localStorage` (`prairie.session`): server URL, access token, profile id.

## API surface (foundation)

1. `POST /api/v1/auth/login` → `access_token`
2. `GET /api/v1/profiles` → pick primary (or first) profile
3. `POST /api/v1/playback/start` with `file_id`, `profile_id`, `codecs_*`, optional forced `play_method`
4. Play `stream_url` (token appended as query when needed)

The home screen is a **file ID debug launcher** for this foundation slice; library browse is follow-up work.

## Layout

```
src/
  api/           Prairie /api/v1 client, auth, playback request builder
  platform/      detect + tizen/avplay + webos/starfish adapters
  player/        backend selection, HTML5 host, PlayerHost
  settings/      playback troubleshooting settings + screen
  screens/       Connect, Home, Player
platforms/       Tizen config.xml + webOS appinfo.json stubs
```

## License

GNU Affero General Public License v3.0 (or later) — see [LICENSE](./LICENSE).

This project does **not** copy Moonfin, Enact, or other proprietary TV client source. Player adapters are thin wrappers over documented platform APIs.
