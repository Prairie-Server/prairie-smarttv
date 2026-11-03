import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/src/lib/detail_metadata.dart';

void main() {
  test('episode codes are zero-padded', () {
    expect(episodeCode(1, 2), 'S01E02');
    expect(episodeCode(12, 104), 'S12E104');
    expect(episodeCode(null, 2), isNull);
  });

  test('episode card caption reads "S01E02 · Title"', () {
    expect(episodeCardTitle(seasonNumber: 1, episodeNumber: 2, title: 'Pilot'), 'S01E02 · Pilot');
    expect(episodeCardTitle(seasonNumber: 1, episodeNumber: 2, title: ' '), 'S01E02');
    expect(episodeCardTitle(title: 'Pilot'), 'Pilot');
  });

  test('episode card meta line is air date and runtime', () {
    expect(episodeCardMeta(airDate: '2024-03-04', runtimeMinutes: 42), 'Mar 4, 2024 · 42m');
    expect(episodeCardMeta(runtimeMinutes: 65), '1h 5m');
    expect(episodeCardMeta(airDate: '2024-03-04'), 'Mar 4, 2024');
    expect(episodeCardMeta(), isNull);
  });
}
