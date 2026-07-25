# Tizen packaging notes

1. Run `npm run build:tizen` — copies Vite `dist/` into `dist-tizen/` with this `config.xml`.
2. Add `platforms/tizen/icon.png` (512×512 recommended) before store packaging.
3. Package with Tizen Studio or CLI:

```bash
tizen package -t wgt -s <profile> -- dist-tizen
```

Privileges: internet + AVPlay (`http://developer.samsung.com/privilege/avplay`).
