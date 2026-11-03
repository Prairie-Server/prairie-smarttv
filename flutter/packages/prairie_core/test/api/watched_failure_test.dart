import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('watchedFailureMessage (Android #706)', () {
    test("keeps the server's reason", () {
      final error = ApiError('Forbidden', 403, null, {'detail': 'This profile cannot change watch state.'});
      expect(
        watchedFailureMessage(watched: true, error: error),
        "Couldn't mark as watched. This profile cannot change watch state.",
      );
    });

    test('a bare HTTP error or a network failure says Try again', () {
      expect(
        watchedFailureMessage(watched: false, error: ApiError('Bad Gateway', 502)),
        "Couldn't mark as unwatched. Try again.",
      );
      expect(
        watchedFailureMessage(watched: true, error: StateError('offline')),
        "Couldn't mark as watched. Try again.",
      );
    });
  });
}
