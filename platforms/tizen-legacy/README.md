# Tizen legacy packaging

**Prairie Lite** is a second installable app for Samsung TVs with older WebKits (~Tizen 5.5 / Chromium M69). The modern package (`platforms/tizen/`) stays the primary client for Tizen 6.0+.

Install `required_version` is **2.3** on both packages (Litefin-style) so Apps2Samsung Public signing works. Pick the build for the engine, not the install floor:

| Artifact                      | App          | Package id   | Engine                         |
| ----------------------------- | ------------ | ------------ | ------------------------------ |
| `Prairie-*-tizen*.wgt`        | Prairie      | `PrairieApp` | Vite `es2019` + ES modules     |
| `Prairie-*-tizen-legacy*.wgt` | Prairie Lite | `PrairieLte` | Chrome 69 / SystemJS downlevel |

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

Same as `platforms/tizen/README.md` — Public Apps2Samsung signing is enough; see that README for optional CI secrets.
