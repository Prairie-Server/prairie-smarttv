# flutter_secure_storage_webos (Prairie fork)

Path fork of
[`lg-flutter-webos/plugins` → `packages/flutter_secure_storage`](https://github.com/lg-flutter-webos/plugins/tree/main/packages/flutter_secure_storage).

Upstream still depends on `flutter_secure_storage_platform_interface: ^1.1.0`,
which cannot solve with `flutter_secure_storage: ^10` (`^2.0.1`). The method
surface is API-compatible; this fork only bumps the platform interface constraint.

This package is a member of the `flutter/packages` pub workspace (with
`prairie_webos`). Always run `flutter pub get` from `flutter/packages/` so the
shared `package_config` is generated — analyzing this directory alone without
workspace resolution produces false `package:flutter/services.dart` / 
`FlutterSecureStoragePlatform` errors.

Copyright remains with LG Electronics (see `LICENSE`).
