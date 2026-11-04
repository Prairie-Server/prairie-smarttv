import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:prairie_core/src/lib/trailer_rail.dart';

ItemDetail _detail(Map<String, dynamic> extra) => ItemDetail.fromJson({
  'content_id': 'movie:1',
  'type': 'movie',
  'title': 'Heat',
  ...extra,
});

void main() {
  test('local extras lead, then YouTube videos, each in server order', () {
    final detail = _detail({
      'videos': [
        {'site': 'YouTube', 'site_key': 'abc', 'name': 'Official Trailer', 'kind': 'trailer', 'is_official': true},
        {'site': 'Vimeo', 'site_key': 'v1', 'name': 'Elsewhere', 'kind': 'clip'},
        {'site': 'youtube', 'site_key': 'def', 'kind': 'teaser'},
        {'site': 'YouTube', 'site_key': '  ', 'kind': 'trailer'},
        {'site': 'YouTube', 'site_key': 'abc', 'name': 'Repeat', 'kind': 'trailer'},
      ],
      'extras': [
        {
          'content_id': 'extra:1',
          'kind': 'behind_the_scenes',
          'duration_seconds': 125,
          'still_url': '/art/still.jpg',
          'still_thumbhash': 'hash',
        },
        {'content_id': 'extra:2', 'kind': 'featurette', 'title': 'Making Heat', 'duration_seconds': 3725},
      ],
    });
    final rail = trailerRailEntries(detail);
    expect(rail.map((e) => e.key), ['local:extra:1', 'local:extra:2', 'remote:YouTube:abc', 'remote:youtube:def']);
    expect(rail.map((e) => e.title), ['Behind the Scenes', 'Making Heat', 'Official Trailer', 'Teaser']);
    expect(rail.map(trailerRailSecondaryLine), ['2:05', '1:02:05', 'YouTube', 'YouTube']);
    expect(rail.first.thumbnailUrl, '/art/still.jpg');
    expect(rail.first.thumbhash, 'hash');
    expect(rail[2].thumbnailUrl, 'https://i.ytimg.com/vi/abc/hqdefault.jpg');
  });

  test('a title without extras or videos has no rail', () {
    expect(trailerRailEntries(_detail({})), isEmpty);
  });

  test('YouTube videos open at the watch-page link', () {
    expect(youTubeWatchUrl('dQw4w9WgXcQ'), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
  });

  test('kind labels read as words', () {
    expect(extraKindLabel('deleted-scene'), 'Deleted Scene');
    expect(extraKindLabel('short_film'), 'Short Film');
    expect(extraKindLabel(''), 'Extra');
  });
}
