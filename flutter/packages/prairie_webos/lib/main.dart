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
    debugPrint(
      'prairie.tv_capabilities: versionMajor=$major versionMinor=$minor parsed=$version '
      'codecsVideo=${caps.codecsVideo} maxAudioChannels=${caps.maxAudioChannels}',
    );
  } catch (err, stack) {
    // Probe failed (emulator / missing plugin) — keep defaults without AV1.
    // Logged (not swallowed) so a failed probe is distinguishable from a
    // genuinely AV1-incapable TV when diagnosing an unexpected transcode.
    debugPrint('prairie.tv_capabilities: capability probe failed — falling back to defaults (no AV1): $err\n$stack');
  }

  runApp(
    ProviderScope(
      overrides: [
        videoBackendFactoryProvider.overrideWith(
          (ref) => ({bool enableDiagnostics = false}) => WebosVideoBackend(
            beaconClient: enableDiagnostics ? ref.read(apiClientProvider) : null,
            beaconServerUrl: enableDiagnostics ? () => ref.read(sessionProvider)?.serverUrl : null,
          ),
        ),
        tvCapabilitiesProvider.overrideWithValue(caps),
        clientIdentityProvider.overrideWithValue(
          ClientIdentity.smartTv(platformLabel: 'webOS', devicePlatform: 'webos'),
        ),
      ],
      child: const PrairieApp(),
    ),
  );
}
