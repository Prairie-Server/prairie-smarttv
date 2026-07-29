import 'package:device_info_plus_webos/device_info_plus_webos.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

import 'platform/webos_video_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  TvPlaybackCapabilities caps = TvPlaybackCapabilities.defaults;
  try {
    final info = await DeviceInfoWebOSPlugin().webosInfo;
    final major = info.versionMajor ?? 0;
    final minor = info.versionMinor ?? 0;
    final version = major + (minor / 10.0);
    caps = buildWebosCapabilities(
      webosVersion: version,
      screenWidth: info.screenWidth ?? 0,
      screenHeight: info.screenHeight ?? 0,
      hdr10: info.hdr10,
      uhd: info.uhd,
      nativePlayerAvailable: true,
    );
  } catch (_) {
    // Probe failed (emulator / missing plugin) — keep defaults without AV1.
  }

  runApp(
    ProviderScope(
      overrides: [
        videoBackendFactoryProvider.overrideWithValue(({bool enableDiagnostics = false}) => WebosVideoBackend()),
        tvCapabilitiesProvider.overrideWithValue(caps),
        clientIdentityProvider.overrideWithValue(
          ClientIdentity.smartTv(platformLabel: 'webOS', devicePlatform: 'webos'),
        ),
      ],
      child: const PrairieApp(),
    ),
  );
}
