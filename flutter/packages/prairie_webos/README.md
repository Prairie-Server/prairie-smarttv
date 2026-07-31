# prairie_webos

Prairie Smart TV client for LG webOS, built with [flutter-webos](https://github.com/lg-flutter-webos/flutter-webos).

## Native plugins

Git dependencies from https://github.com/lg-flutter-webos/plugins (see `doc/plugin-list.md`):

| Package | Path | Purpose |
| --- | --- | --- |
| `video_player_drm` | `packages/video_player_drm` | Playback (multi-audio, subs, DRM) |
| `device_info_plus_webos` | `packages/device_info_plus` | Device tier + capabilities |
| `shared_preferences_webos` | `packages/shared_preferences` | Settings / session identity |
| `flutter_secure_storage_webos` | `packages/flutter_secure_storage` | Tokens |

## Platform wiring

- `lib/platform/webos_video_backend.dart` — `VideoBackend` over `video_player_drm`
- `lib/platform/device_tier_webos.dart` — `PerformanceTier` from device info
- `lib/main.dart` — overrides `videoBackendFactoryProvider` + `tvCapabilitiesProvider`

## appinfo.json requirements

- `"transparent": true` — required for the hardware video plane
- `requiredACG`: `systemconfig.query` (device info), `securitykey.operation` (secure storage)

## Build

```bash
# From repo flutter/ (requires flutter-webos + NDK on Linux)
../scripts/build-webos.sh --obfuscate
```
