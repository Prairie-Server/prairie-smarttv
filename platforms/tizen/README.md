# Tizen packaging notes

1. Run `npm run build:tizen` — copies Vite `dist/` into `dist-tizen/` with this `config.xml` and `icon.png`.
2. Replace `platforms/tizen/icon.png` (512×512 amber placeholder) with the final brand mark before store packaging. The build **fails** if the icon is missing.
3. Package with Tizen Studio or CLI:

```bash
tizen package -t wgt -s <profile> -- dist-tizen
```

Privileges: internet + AVPlay (`http://developer.samsung.com/privilege/avplay`).
