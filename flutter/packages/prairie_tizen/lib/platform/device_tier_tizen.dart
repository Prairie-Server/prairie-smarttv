import 'package:device_info_plus_tizen/device_info_plus_tizen.dart';
import 'package:prairie_core/prairie_core.dart';

/// Detects this device's [PerformanceTier] using `device_info_plus_tizen`.
///
/// Mirrors the Tizen branch of `detectHardwareTier` in performanceTier.ts,
/// reading platform version + RAM from Tizen's system API instead of a UA
/// string.
Future<PerformanceTier> detectTizenHardwareTier() async {
  final info = await DeviceInfoPluginTizen().tizenInfo;
  return detectHardwareTier(
    platform: TvPlatform.tizen,
    platformVersion: double.tryParse(info.platformVersion ?? ''),
    physicalRamMb: info.physicalRamSize,
  );
}
