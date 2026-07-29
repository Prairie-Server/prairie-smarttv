import 'package:device_info_plus_tizen/device_info_plus_tizen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

import 'platform/avplay_video_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  TvPlaybackCapabilities caps = TvPlaybackCapabilities.defaults;
  try {
    final info = await DeviceInfoPluginTizen().tizenInfo;
    final version = double.tryParse(info.platformVersion ?? '') ?? 0;
    caps = buildTizenCapabilities(
      tizenVersion: version,
      screenWidth: info.screenWidth,
      screenHeight: info.screenHeight,
      avplayAvailable: true,
    );
  } catch (_) {
    // Probe failed (emulator / missing plugin) — keep defaults without AV1.
  }

  runApp(
    ProviderScope(
      overrides: [
        videoBackendFactoryProvider.overrideWithValue(() => AvplayVideoBackend()),
        tvCapabilitiesProvider.overrideWithValue(caps),
      ],
      child: const PrairieApp(),
    ),
  );
}
