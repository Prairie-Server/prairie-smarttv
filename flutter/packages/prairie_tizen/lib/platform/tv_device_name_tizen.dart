import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Channel served by the C# runner (`tizen/App.cs`), which answers
/// `getDeviceName` with `Tizen.System.SystemSettings.DeviceName`.
const tizenDeviceNameChannel = MethodChannel('org.prairieserver.prairie/device_name');

/// The name the owner gave this TV, or null when the platform can't say
/// (older runner, unsupported profile, slow reply). Callers fall back to the
/// generic `Prairie Smart TV (Tizen)` through `ClientIdentity.smartTv`.
Future<String?> readTizenDeviceName() async {
  try {
    return await tizenDeviceNameChannel
        .invokeMethod<String>('getDeviceName')
        .timeout(const Duration(seconds: 2));
  } catch (err) {
    debugPrint('prairie.device_name: Tizen device name unavailable: $err');
    return null;
  }
}
