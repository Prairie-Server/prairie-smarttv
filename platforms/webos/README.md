# webOS packaging (1.0)

## Build package staging / `.ipk`

```bash
npm run package:webos
```

This runs `build:webos` (Vite → `dist-webos/` with `appinfo.json` + icons).

- If [`@webos-tools/cli`](https://www.npmjs.com/package/@webos-tools/cli) (`ares-package`) is on your `PATH`, a real `.ipk` is written under `artifacts/`.
- Otherwise an unsigned staging zip is written as `artifacts/Prairie-1.0.0-webos-unsigned.zip`. Create the `.ipk` with:

```bash
npm install -g @webos-tools/cli
ares-package dist-webos -o artifacts
```

## Sign for LG Content Store

1. Enroll in the [LG Developer Partner](https://webostv.developer.lge.com/) program and create a signing certificate.
2. Package with your partner credentials (LG’s store tools / `ares-package` with the configured profile).
3. Submit the signed `.ipk` through LG’s seller console.

Sideload / emulator installs can use the unsigned `.ipk` from `ares-package` with developer mode enabled on the TV.

## Playback notes

Playback uses an HTML5 `<video>` path with Starfish-style `mediaOption` / `mediaPreferred` hints when available.

## Icons

`icon.png` (80×80) and `largeIcon.png` (130×130) are required by `appinfo.json`. The build **fails** if either is missing.
