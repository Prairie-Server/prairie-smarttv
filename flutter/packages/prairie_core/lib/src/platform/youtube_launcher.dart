import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a YouTube video in the TV's own YouTube app. Platform apps provide
/// it (Tizen through an app control, webOS through the application manager);
/// `prairie_core` only knows this contract.
abstract class YouTubeLauncher {
  /// Asks the TV to open [watchUrl] (a `https://www.youtube.com/watch?v=`
  /// link, see `youTubeWatchUrl`) for the video [videoId]. Completes with
  /// false when the TV has no YouTube app or refused the launch, so the
  /// caller can offer another way to watch; never throws.
  Future<bool> openWatchPage({required String videoId, required String watchUrl});
}

/// The platform's launcher, or null where the TV can't hand off to YouTube
/// (tests, desktop builds). Overridden in each platform app's `main()`.
final youTubeLauncherProvider = Provider<YouTubeLauncher?>((ref) => null);
