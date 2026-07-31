# Prairie Smart TV

AGPL-3.0 Flutter clients for **Samsung Tizen** and **LG webOS**, talking to Prairie over native `/api/v1`.

**Version 1.0.0** — Prairie Dusk UI: deep slate `#141820`, amber `#e0a84a`, Sora + Fraunces.

The TypeScript/React web app has been removed; Flutter is the only client tree.

## Layout

```
flutter/
  packages/
    prairie_core/     # shared Dart: API, screens, VideoBackend contract
    prairie_tizen/    # Samsung Tizen (flutter-tizen) + AVPlay
    prairie_webos/    # LG webOS (flutter-webos) + video_player_drm
  scripts/            # Tizen api-version stamps + package builds
```

See [flutter/README.md](flutter/README.md) for toolchain setup, multi–api-version Tizen packages, and local run instructions.

## What’s included

- Connect to a Prairie server (username / password + Quick Connect QR opt-in)
- Multi-server registry + LAN discovery
- Profile picker (PIN unlock when required)
- Home rails, libraries, collections, search
- Live TV channels / EPG guide / recordings (Record now / Record next)
- Item detail with Play / Resume / Start Over and related rails
- Native player: progress reporting, ±15s seek, audio switch, subtitles, session teardown
- Upgrade-safe persistence for session, settings, and last server URL
- Playback backends: Tizen AVPlay / webOS DRM player
- Troubleshooting settings: force direct / force transcode, AV1 advertise overrides, performance mode

## CI / packaging

GitHub Actions run Flutter analyze/test and (when SDKs are present) produce four release packages: webOS `.ipk` plus Tizen TPKs for api-versions `6.0`, `6.5`, and `10.0`.

## License

AGPL-3.0 — see [LICENSE](LICENSE).
