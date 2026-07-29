import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('isPlaybackSessionGone', () {
    test('true for 404 session-gone codes', () {
      expect(
        isPlaybackSessionGone(ApiError('gone', 404, 'playback_session_not_found')),
        isTrue,
      );
      expect(isPlaybackSessionGone(ApiError('gone', 404, 'not_found')), isTrue);
      expect(isPlaybackSessionGone(ApiError('gone', 404, 'session_not_found')), isTrue);
      expect(isPlaybackSessionGone(ApiError('gone', 404)), isTrue);
      expect(isPlaybackSessionGone(ApiError('gone', 404, '')), isTrue);
    });

    test('false for other statuses or codes', () {
      expect(isPlaybackSessionGone(ApiError('nope', 500, 'playback_session_not_found')), isFalse);
      expect(isPlaybackSessionGone(ApiError('nope', 404, 'forbidden')), isFalse);
      expect(isPlaybackSessionGone(StateError('x')), isFalse);
    });
  });
}
