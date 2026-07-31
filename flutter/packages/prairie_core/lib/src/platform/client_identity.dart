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

  /// Build a versioned Tizen / webOS identity.
  factory ClientIdentity.smartTv({
    required String platformLabel,
    required String devicePlatform,
    String version = '1.0.0',
  }) {
    final label = platformLabel.trim();
    return ClientIdentity(
      userAgent: 'Prairie-SmartTV/$version ($label; Flutter)',
      devicePlatform: devicePlatform,
      deviceName: 'Prairie Smart TV ($label)',
    );
  }
}
