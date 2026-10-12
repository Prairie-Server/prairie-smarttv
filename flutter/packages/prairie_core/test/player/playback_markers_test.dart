import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

MarkerRegion _r(MarkerKind kind, double start, double end) => MarkerRegion(kind: kind, start: start, end: end);

void main() {
  group('parseMarkerRegions', () {
    test('prefers v2 marker_segments, keeping repeated kinds, sorted and valid only', () {
      final regions = parseMarkerRegions({
        'marker_segments': [
          {'kind': 'credits', 'start_seconds': 1300, 'end_seconds': 1400},
          {'kind': 'intro', 'start_seconds': 60, 'end_seconds': 90},
          {'kind': 'intro', 'start_seconds': 600, 'end_seconds': 620},
          {'kind': 'recap', 'start_seconds': 50, 'end_seconds': 40}, // inverted: dropped
          {'kind': 'bogus', 'start_seconds': 1, 'end_seconds': 2}, // unknown kind: dropped
        ],
        // Ignored when marker_segments is present.
        'recap': {'start_seconds': 0, 'end_seconds': 30},
      });
      expect(regions, [
        _r(MarkerKind.intro, 60, 90),
        _r(MarkerKind.intro, 600, 620),
        _r(MarkerKind.credits, 1300, 1400),
      ]);
    });

    test('falls back to singular v2 and v1 ranges', () {
      expect(parseMarkerRegions({
        'intro': {'start_seconds': 10, 'end_seconds': 40},
      }), [_r(MarkerKind.intro, 10, 40)]);
      expect(parseMarkerRegions({
        'credits': {'start': 1200, 'end': 1260},
        'recap': {'start': 0, 'end': 45},
      }), [_r(MarkerKind.recap, 0, 45), _r(MarkerKind.credits, 1200, 1260)]);
    });
  });

  group('autoplayRegionStart', () {
    test('starts at credits that run to the end', () {
      expect(autoplayRegionStart([_r(MarkerKind.credits, 1300, 1399.5)], 1400, allowPreview: false), 1300);
    });

    test('extends over a trailing preview only when allowed', () {
      final regions = [_r(MarkerKind.credits, 1300, 1350), _r(MarkerKind.preview, 1350, 1400)];
      expect(autoplayRegionStart(regions, 1400, allowPreview: true), 1300);
      // Preview not allowed: the credits stop short of the end, so nothing
      // trailing is marked and the episode plays out.
      expect(autoplayRegionStart(regions, 1400, allowPreview: false), isNull);
    });

    test('never spans an unmarked scene between credits and the end', () {
      expect(autoplayRegionStart([_r(MarkerKind.credits, 1200, 1260)], 1400, allowPreview: true), isNull);
    });

    test('no duration or no markers: no region', () {
      expect(autoplayRegionStart([_r(MarkerKind.credits, 1300, 1400)], 0, allowPreview: false), isNull);
      expect(autoplayRegionStart(const [], 1400, allowPreview: false), isNull);
    });
  });

  test('activeMarker is start-inclusive, end-exclusive', () {
    final regions = [_r(MarkerKind.intro, 60, 90)];
    expect(activeMarker(regions, MarkerKind.intro, 60), isNotNull);
    expect(activeMarker(regions, MarkerKind.intro, 89.9), isNotNull);
    expect(activeMarker(regions, MarkerKind.intro, 90), isNull);
    expect(activeMarker(regions, MarkerKind.credits, 70), isNull);
  });

  test('SeriesContext finds neighbors across season boundaries', () {
    const series = SeriesContext(seriesId: 's', episodes: [
      EpisodeRef(contentId: 'e1x9', title: 'Finale', seasonNumber: 1, episodeNumber: 9),
      EpisodeRef(contentId: 'e2x1', title: 'Premiere', seasonNumber: 2, episodeNumber: 1),
    ]);
    expect(series.nextOf('e1x9')?.contentId, 'e2x1');
    expect(series.previousOf('e2x1')?.contentId, 'e1x9');
    expect(series.previousOf('e1x9'), isNull);
    expect(series.nextOf('e2x1'), isNull);
    expect(series.nextOf('unknown'), isNull);
  });

  test('watch detail parses v2 string ids, duration_seconds and markers', () {
    final watch = WatchDetail.fromJson({
      'content_id': 'episode:x-s01e01',
      'type': 'episode',
      'title': 'Pilot',
      'series_id': 'series:x',
      'series_title': 'X',
      'season_number': 1,
      'episode_number': 1,
      'user_data': {'last_file_id': '42', 'played': false},
      'versions': [
        {
          'file_id': '42',
          'duration_seconds': 1400,
          'marker_segments': [
            {'kind': 'intro', 'start_seconds': 60, 'end_seconds': 90},
          ],
        },
      ],
    });
    expect(watch.versions.single.fileId, 42);
    expect(watch.versions.single.duration, 1400);
    expect(watch.versions.single.markers.single.kind, MarkerKind.intro);
    expect(watch.userData?.lastFileId, 42);
    expect(watch.seriesTitle, 'X');
  });
}
