# webOS packaging notes

1. Run `npm run build:webos` — copies Vite `dist/` into `dist-webos/` with `appinfo.json`.
2. Add icon placeholders (`icon.png`, `largeIcon.png`) under `platforms/webos/` before packaging.
3. Package with ares-cli:

```bash
ares-package dist-webos
```

Playback uses an HTML5 `<video>` path with Starfish-style `mediaOption` / `mediaPreferred` hints when available.
