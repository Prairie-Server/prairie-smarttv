import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  test('parses a notification page', () {
    final page = NotificationPage.fromJson({
      'read_cutoff': 'rc_123',
      'items': [
        {
          'id': 'n1',
          'type': 'episode.available',
          'profile_id': 'p1',
          'reason_flags': {'favorite': true},
          'created_at': '2026-10-12T08:00:00.000Z',
          'read_at': null,
          'series_id': 's1',
          'series_title': 'Severance',
          'episode_id': 'e1',
          'episode_title': 'Hello, Ms. Cobel',
          'season_number': 2,
          'episode_number': 1,
        },
        {
          'id': 'n2',
          'type': 'request.declined',
          'profile_id': 'p1',
          'reason_flags': {'title': 'Dune', 'reason': 'Already in library'},
          'created_at': '2026-10-11T08:00:00.000Z',
          'read_at': '2026-10-11T09:00:00.000Z',
        },
      ],
    });

    expect(page.readCutoff, 'rc_123');
    final episode = page.items[0];
    expect(episode.unread, isTrue);
    expect(episode.createdAt, DateTime.utc(2026, 10, 12, 8));
    expect(episode.title, 'Severance');
    expect(episode.description, 'S02E01 — Hello, Ms. Cobel');
    expect(episode.contentId, 'e1');

    final declined = page.items[1];
    expect(declined.unread, isFalse);
    expect(declined.title, 'Dune');
    expect(declined.description, 'Your request was declined — Already in library');
    expect(declined.contentId, isNull);
  });

  test('tolerates unknown types and odd reason_flags', () {
    final n = AppNotification.fromJson({
      'id': 'n3',
      'type': 'future.thing',
      'reason_flags': 'not-an-object',
      'created_at': '2026-10-12T08:00:00.000Z',
      'read_at': null,
    });
    expect(n.title, 'Notification');
    expect(n.description, 'future.thing');
    expect(n.reasonFlags, isEmpty);
    expect(n.markedRead(DateTime(2026)).unread, isFalse);
  });

  test('formatNotificationTime', () {
    final now = DateTime.utc(2026, 10, 12, 12);
    expect(formatNotificationTime(now.subtract(const Duration(seconds: 20)), now: now), 'Just now');
    expect(formatNotificationTime(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
    expect(formatNotificationTime(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
    expect(formatNotificationTime(now.subtract(const Duration(days: 2)), now: now), '2d ago');
  });
}
