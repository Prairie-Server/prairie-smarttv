/// Release version stamped into the build by flutter/scripts/build-tizen.sh /
/// build-webos.sh (`--dart-define=PRAIRIE_APP_VERSION=…`, from the release
/// tag); empty in local/dev builds and tests.
const stampedAppVersion = String.fromEnvironment('PRAIRIE_APP_VERSION');

/// Identifies this TV client to Prairie (HTTP User-Agent + device headers).
///
/// Platform apps override [clientIdentityProvider] so admin/session UIs and
/// logs show `Prairie-SmartTV/… (Tizen)` / `(webOS)` instead of Dio's default
/// `Dart/3.x` User-Agent.
class ClientIdentity {
  const ClientIdentity({
    this.userAgent = defaultUserAgent,
    this.devicePlatform = 'smarttv',
    this.deviceName = 'Prairie Smart TV',
    this.appVersion = '1.0.0',
    this.appBuild = '',
    this.appChannel = 'release',
  });

  /// Matches the TS update-check UA (`Prairie-SmartTV`) when no platform
  /// override is installed (tests / shared package hosts).
  static const defaultUserAgent = 'Prairie-SmartTV';

  /// Full HTTP `User-Agent` string (e.g. `Prairie-SmartTV/1.0.0 (Tizen; Flutter)`).
  final String userAgent;

  /// Value for `X-Prairie-Device-Platform` and device-login `device_platform`.
  final String devicePlatform;

  /// Value for `X-Prairie-Device-Name` and device-login `device_name`.
  final String deviceName;

  /// Native protocol-v3 playback identity fields.
  final String appVersion;
  final String appBuild;
  final String appChannel;

  /// Build a versioned Tizen / webOS identity.
  ///
  /// [deviceName] is the name the owner gave the TV in its system settings
  /// (read by the platform app at startup). It is cleaned with
  /// [fitTvDeviceName]; when absent or blank the identity falls back to
  /// `Prairie Smart TV (<platformLabel>)`.
  factory ClientIdentity.smartTv({
    required String platformLabel,
    required String devicePlatform,
    String? deviceName,
    String version = stampedAppVersion == '' ? '1.0.0' : stampedAppVersion,
    String build = '',
    String channel = 'release',
  }) {
    final label = platformLabel.trim();
    return ClientIdentity(
      userAgent: 'Prairie-SmartTV/$version ($label; Flutter)',
      devicePlatform: devicePlatform,
      deviceName: fitTvDeviceName(deviceName) ?? 'Prairie Smart TV ($label)',
      appVersion: version,
      appBuild: build,
      appChannel: channel,
    );
  }
}

/// Longest device name sent to the server, in UTF-8 bytes (matches the
/// Android TV client's `TvDeviceName`).
const tvDeviceNameMaxBytes = 63;

/// Clean a TV's user-given name for `X-Prairie-Device-Name` / device-login
/// `device_name`: control characters become spaces, whitespace runs collapse,
/// the result is trimmed and cut to [tvDeviceNameMaxBytes] UTF-8 bytes on a
/// character boundary. Returns null when nothing usable is left so callers
/// fall back to the generic name.
String? fitTvDeviceName(String? raw) {
  if (raw == null) return null;
  final cleaned = raw
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return null;
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in cleaned.runes) {
    final size = rune < 0x80
        ? 1
        : rune < 0x800
            ? 2
            : rune < 0x10000
                ? 3
                : 4;
    if (bytes + size > tvDeviceNameMaxBytes) break;
    bytes += size;
    out.writeCharCode(rune);
  }
  final fitted = out.toString().trim();
  return fitted.isEmpty ? null : fitted;
}

/// Pull the TV name out of a webOS
/// `luna://com.webos.settingsservice/getSystemSettings` reply for category
/// `network`, key `deviceName` (`{returnValue: true, settings: {deviceName:
/// ...}}`). Returns null for a failed call or a missing / non-string value.
String? webosDeviceNameFromSettings(Map<String, dynamic>? reply) {
  if (reply == null || reply['returnValue'] == false) return null;
  final settings = reply['settings'];
  if (settings is! Map) return null;
  final name = settings['deviceName'];
  return name is String ? name : null;
}
