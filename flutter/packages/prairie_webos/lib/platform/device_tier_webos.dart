import 'package:device_info_plus_webos/device_info_plus_webos.dart';
import 'package:prairie_core/prairie_core.dart';

/// Parses webOS `ddrSize` strings such as `"2G"`, `"1.5G"`, `"2048M"` into MB.
int? parseWebosDdrSizeMb(String? ddrSize) {
  if (ddrSize == null) return null;
  final raw = ddrSize.trim().toUpperCase();
  if (raw.isEmpty) return null;
  final match = RegExp(r'^([\d.]+)\s*([GMK])?B?$').firstMatch(raw);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null || value <= 0) return null;
  switch (match.group(2) ?? 'M') {
    case 'G':
      return (value * 1024).round();
    case 'K':
      return (value / 1024).round().clamp(1, 1 << 30);
    case 'M':
    default:
      return value.round();
  }
}

/// Detects this device's [PerformanceTier] using `device_info_plus_webos`.
Future<PerformanceTier> detectWebosHardwareTier() async {
  final info = await DeviceInfoWebOSPlugin().webosInfo;
  final major = info.versionMajor ?? 0;
  final minor = info.versionMinor ?? 0;
  final version = major + (minor / 10.0);
  return detectHardwareTier(
    platform: TvPlatform.webos,
    platformVersion: major > 0 ? version : null,
    physicalRamMb: parseWebosDdrSizeMb(info.ddrSize),
  );
}
