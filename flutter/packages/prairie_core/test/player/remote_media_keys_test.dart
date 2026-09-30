import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  test('maps remote transport keys to their actions', () {
    expect(remoteMediaActionFor(LogicalKeyboardKey.mediaPlayPause), RemoteMediaAction.playPause);
    expect(remoteMediaActionFor(LogicalKeyboardKey.mediaPlay), RemoteMediaAction.play);
    expect(remoteMediaActionFor(LogicalKeyboardKey.mediaPause), RemoteMediaAction.pause);
    expect(remoteMediaActionFor(LogicalKeyboardKey.mediaStop), RemoteMediaAction.stop);
    expect(remoteMediaActionFor(LogicalKeyboardKey.mediaFastForward), RemoteMediaAction.fastForward);
    expect(remoteMediaActionFor(LogicalKeyboardKey.mediaRewind), RemoteMediaAction.rewind);
  });

  test('leaves navigation keys alone', () {
    for (final key in [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.goBack]) {
      expect(remoteMediaActionFor(key), isNull);
    }
  });
}
