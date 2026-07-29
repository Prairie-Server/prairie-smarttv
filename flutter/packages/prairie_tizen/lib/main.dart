import 'dart:developer' as developer;

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
    final rawVersion = info.platformVersion;
    final version = double.tryParse(rawVersion ?? '') ?? 0;
    caps = buildTizenCapabilities(
      tizenVersion: version,
      screenWidth: info.screenWidth,
      screenHeight: info.screenHeight,
      avplayAvailable: true,
    );
    developer.log(
      'Tizen capability probe: platformVersion=$rawVersion parsed=$version codecsVideo=${caps.codecsVideo}',
      name: 'prairie.tv_capabilities',
    );
  } catch (err, stack) {
    // Probe failed (emulator / missing plugin) — keep defaults without AV1.
    // Logged (not swallowed) so a failed probe is distinguishable from a
    // genuinely AV1-incapable TV when diagnosing an unexpected transcode.
    developer.log(
      'Tizen capability probe failed — falling back to defaults (no AV1)',
      name: 'prairie.tv_capabilities',
      error: err,
      stackTrace: stack,
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        videoBackendFactoryProvider.overrideWithValue(() => AvplayVideoBackend()),
        tvCapabilitiesProvider.overrideWithValue(caps),
        clientIdentityProvider.overrideWithValue(
          ClientIdentity.smartTv(platformLabel: 'Tizen', devicePlatform: 'tizen'),
        ),
      ],
      child: const PrairieApp(),
    ),
  );
}
