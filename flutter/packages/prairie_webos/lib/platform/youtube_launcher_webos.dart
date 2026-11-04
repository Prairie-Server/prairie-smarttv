import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:webos_service_bridge/webos_service_bridge.dart';

/// The flutter-webos embedder's own plugin channel; its `app_manager/launch`
/// starts another app (what lg-flutter-webos' url_launcher uses).
const _webosPluginChannel = MethodChannel('webos_plugin');

/// LG's YouTube app.
const webosYouTubeAppId = 'youtube.leanback.v4';

/// Opens YouTube trailers in LG's YouTube app with the watch-page link as its
/// `contentTarget`. Needs the `application.launcher` ACG in
/// `webos/meta/appinfo.json`. False when the app is missing or the launch is
/// refused.
class WebosYouTubeLauncher implements YouTubeLauncher {
  const WebosYouTubeLauncher();

  @override
  Future<bool> openWatchPage({required String videoId, required String watchUrl}) async {
    final params = <String, dynamic>{'contentTarget': watchUrl};
    try {
      final launched = await _webosPluginChannel
          .invokeMethod<bool>('app_manager/launch', <String, dynamic>{'id': webosYouTubeAppId, 'params': params})
          .timeout(const Duration(seconds: 5));
      if (launched == true) return true;
    } catch (err) {
      debugPrint('prairie.youtube: embedder launch failed, trying luna: $err');
    }
    try {
      final reply = await WebOSServiceBridge.callOneReply(
        'luna://com.webos.applicationManager/launch',
        payload: {'id': webosYouTubeAppId, 'params': params},
      ).timeout(const Duration(seconds: 5));
      return reply?['returnValue'] == true;
    } catch (err) {
      debugPrint('prairie.youtube: webOS YouTube launch failed: $err');
      return false;
    }
  }
}
