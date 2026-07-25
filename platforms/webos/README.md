# webOS packaging notes

1. Run `npm run build:webos` — copies Vite `dist/` into `dist-webos/` with `appinfo.json` and icons.
2. Replace `icon.png` / `largeIcon.png` amber placeholders with final brand marks before store packaging. The build **fails** if either icon is missing.
3. Package with ares-cli:

```bash
ares-package dist-webos
```

Playback uses an HTML5 `<video>` path with Starfish-style `mediaOption` / `mediaPreferred` hints when available.
