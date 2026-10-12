import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  CalendarEvent episode(String id, String airDate, {String? airAt}) => CalendarEvent.fromJson({
    'content_id': id,
    'type': 'episode',
    'title': 'Severance',
    'air_date': airDate,
    'local_air_date': airDate,
    'air_at': ?airAt,
    'series_id': 'series:severance',
    'season_number': 2,
    'episode_number': 1,
    'episode_title': 'Hello, Ms. Cobel',
    'watched': false,
    'badges': <String>[],
  });

  test('parses an event and formats its episode label', () {
    final event = episode('episode:a', '2026-10-12');
    expect(event.episodeLabel, 'S02E01 · Hello, Ms. Cobel');
    expect(event.detailContentId, 'series:severance');
    expect(event.airAt, isNull);
  });

  test('groups by local day, drops past days, and labels Today/Tomorrow/weekday', () {
    final now = DateTime(2026, 10, 12, 20);
    final airAt = DateTime(2026, 10, 13, 21).toUtc().toIso8601String();
    final days = groupCalendarEvents([
      episode('episode:past', '2026-10-11'),
      episode('episode:later', '2026-10-16'),
      episode('episode:today', '2026-10-12'),
      episode('episode:tomorrow', '2026-10-14', airAt: airAt),
    ], now);
    expect(days.map((d) => d.label), ['Today', 'Tomorrow', 'Friday, Oct 16']);
    expect(days[1].events.single.contentId, 'episode:tomorrow');
  });

  test('drops days past the requested window', () {
    final days = groupCalendarEvents([
      episode('episode:last', '2026-10-25'),
      episode('episode:spill', '2026-10-26'),
    ], DateTime(2026, 10, 12, 20));
    expect(days.single.events.single.contentId, 'episode:last');
  });
}
