# Tizen packaging (1.0)

## Build unsigned `.wgt`

```bash
npm run package:tizen
```

This runs `build:tizen` (Vite → `dist-tizen/` with `config.xml` + `icon.png`) and writes:

`artifacts/Prairie-1.0.0-tizen-unsigned.wgt`

A `.wgt` is a zip of the widget directory. The unsigned artifact is fine for sideload/testing with a developer certificate; **Samsung Seller Office requires a signed package**.

## Sign for store / device

1. Install [Tizen Studio](https://developer.tizen.org/development/tizen-studio) and the TV extensions.
2. Create an author + distributor certificate in **Certificate Manager** (Samsung Seller Office distributor cert for store builds).
3. Package + sign:

```bash
npm run build:tizen
tizen package -t wgt -s <your-security-profile> -- dist-tizen
```

Or: open `dist-tizen` in Tizen Studio → **Project** → **Build Signed Package**.

## Privileges

Declared in `config.xml`:

- `http://tizen.org/privilege/internet`
- `http://tizen.org/privilege/tv.inputdevice`
- `http://developer.samsung.com/privilege/avplay`

## Icons

`platforms/tizen/icon.png` is the Prairie 512×512 app icon. The build **fails** if it is missing.
