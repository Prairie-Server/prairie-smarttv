import 'package:flutter/services.dart';

/// Transport buttons on a TV remote (Samsung's play/pause, or separate
/// play and pause keys, stop, fast-forward and rewind).
enum RemoteMediaAction { playPause, play, pause, stop, fastForward, rewind }

/// Maps a remote's media key to its transport action, or null for any other
/// key. The players handle these directly, whatever has focus: without that,
/// a media key only counted as "any key" and brought the chrome up.
RemoteMediaAction? remoteMediaActionFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.mediaPlayPause) return RemoteMediaAction.playPause;
  if (key == LogicalKeyboardKey.mediaPlay || key == LogicalKeyboardKey.play) return RemoteMediaAction.play;
  if (key == LogicalKeyboardKey.mediaPause || key == LogicalKeyboardKey.pause) return RemoteMediaAction.pause;
  if (key == LogicalKeyboardKey.mediaStop) return RemoteMediaAction.stop;
  if (key == LogicalKeyboardKey.mediaFastForward) return RemoteMediaAction.fastForward;
  if (key == LogicalKeyboardKey.mediaRewind) return RemoteMediaAction.rewind;
  return null;
}

/// Remote keys the TV itself acts on (volume, mute and Home). The players let
/// these pass untouched: otherwise they counted as "any key", so changing the
/// volume brought the chrome up and Home took a second press.
bool isSystemRemoteKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.audioVolumeUp ||
    key == LogicalKeyboardKey.audioVolumeDown ||
    key == LogicalKeyboardKey.audioVolumeMute ||
    key == LogicalKeyboardKey.goHome ||
    key == LogicalKeyboardKey.browserHome ||
    key == LogicalKeyboardKey.home;
