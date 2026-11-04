import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:prairie_core/prairie_core.dart';

/// Channel served by the C# runner (`tizen/App.cs`), which answers
/// `openWatchPage` by launching Samsung's YouTube app with an app control.
const tizenYouTubeChannel = MethodChannel('org.prairieserver.prairie/youtube');

/// Opens YouTube trailers in the TV's YouTube app. False when the app is
/// missing or refused the launch (or the runner predates the channel).
class TizenYouTubeLauncher implements YouTubeLauncher {
  const TizenYouTubeLauncher();

  @override
  Future<bool> openWatchPage({required String videoId, required String watchUrl}) async {
    try {
      final opened = await tizenYouTubeChannel
          .invokeMethod<bool>('openWatchPage', videoId)
          .timeout(const Duration(seconds: 5));
      return opened ?? false;
    } catch (err) {
      debugPrint('prairie.youtube: Tizen YouTube launch failed: $err');
      return false;
    }
  }
}
