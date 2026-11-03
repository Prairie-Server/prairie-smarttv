import 'package:flutter/foundation.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:webos_service_bridge/webos_service_bridge.dart';

/// The name the owner gave this TV (Settings > General > Devices > TV
/// name), read from the luna settings service. Needs the `settings.query`
/// ACG in `webos/meta/appinfo.json`. Returns null when the call fails or is
/// slow; callers fall back to the generic `Prairie Smart TV (webOS)` through
/// `ClientIdentity.smartTv`.
Future<String?> readWebosDeviceName() async {
  try {
    final reply = await WebOSServiceBridge.callOneReply(
      'luna://com.webos.settingsservice/getSystemSettings',
      payload: {
        'category': 'network',
        'keys': ['deviceName'],
      },
    ).timeout(const Duration(seconds: 2));
    final name = webosDeviceNameFromSettings(reply);
    if (name == null) {
      debugPrint('prairie.device_name: webOS settings reply had no deviceName: $reply');
    }
    return name;
  } catch (err) {
    debugPrint('prairie.device_name: webOS device name unavailable: $err');
    return null;
  }
}
