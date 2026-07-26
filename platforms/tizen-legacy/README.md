# Tizen legacy packaging (5.5+)

**Prairie Lite** is a second installable app for Samsung TVs on **Tizen 5.5** (roughly 2020 and some earlier Chromium M69 sets). The modern package (`platforms/tizen/`, `required_version="6.0"`) stays the primary client for 6.0 / 6.5 / 7 / 8.

| Artifact                      | App          | `required_version` | Package id |
| ----------------------------- | ------------ | ------------------ | ---------- |
| `Prairie-*-tizen*.wgt`        | Prairie      | 6.0                | `prairie`  |
| `Prairie-*-tizen-legacy*.wgt` | Prairie Lite | 5.5                | `prairieL` |

Same Samsung Certificate Manager profile can sign both. Distinct package ids let both sit on one TV.

## Build

```bash
npm run package:tizen-legacy
# → artifacts/Prairie-<version>-tizen-legacy-unsigned.wgt
```

Signed (local):

```bash
npm run build:tizen-legacy
TIZEN_DIST_DIR=dist-tizen-legacy TIZEN_SECURITY_PROFILE=<profile> \
  TIZEN_SIGNED_OUT=artifacts/Prairie-<version>-tizen-legacy.wgt npm run sign:tizen
```

Or:

```bash
TIZEN_SECURITY_PROFILE=<profile> npm run package:tizen-legacy
```

## Engine notes

The legacy Vite config (`vite.tizen-legacy.config.ts`) uses `@vitejs/plugin-legacy` targeting **Chrome 69** (SystemJS + polyfills). This is the Moonfin/Litefin-style second package — not a `required_version` tweak on the modern bundle.

React 19 on M69 is best-effort; if a 5.5 TV fails to boot Home/AVPlay, the next step is a thinner Preact/vanilla shell reusing `src/api` + `src/platform/tizen`.

## Secrets / signing

Same as `platforms/tizen/README.md` — see **Generate GitHub signing secrets** there.
