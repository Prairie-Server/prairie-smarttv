# Tizen packaging notes

1. Run `npm run build:tizen` — copies Vite `dist/` into `dist-tizen/` with this `config.xml` and `icon.png`.
2. `platforms/tizen/icon.png` is the Prairie app icon (512×512, resized from the brand 1024 master). The build **fails** if the icon is missing.
3. Package with Tizen Studio or CLI:

```bash
tizen package -t wgt -s <profile> -- dist-tizen
```

Privileges: internet + AVPlay (`http://developer.samsung.com/privilege/avplay`).
