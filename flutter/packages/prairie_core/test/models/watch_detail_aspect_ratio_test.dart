import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('parseAspectRatioString', () {
    test('parses common cinema and broadcast forms', () {
      expect(parseAspectRatioString('16:9'), closeTo(16 / 9, 1e-9));
      expect(parseAspectRatioString('2.39:1'), closeTo(2.39, 1e-9));
      expect(parseAspectRatioString('239:100'), closeTo(2.39, 1e-9));
    });

    test('rejects empty or malformed input', () {
      expect(parseAspectRatioString(null), isNull);
      expect(parseAspectRatioString(''), isNull);
      expect(parseAspectRatioString('garbage'), isNull);
      expect(parseAspectRatioString('2.39'), isNull);
      expect(parseAspectRatioString('1:0'), isNull);
    });
  });

  group('contentAspectRatioFromVideoTrack', () {
    test('prefers pixel dimensions over aspect_ratio string', () {
      final track = VideoTrackInfo(width: 3840, height: 1606, aspectRatio: '2.39:1');
      expect(contentAspectRatioFromVideoTrack(track), closeTo(3840 / 1606, 1e-9));
    });

    test('falls back to aspect_ratio when dimensions are missing', () {
      final track = VideoTrackInfo(aspectRatio: '2.39:1');
      expect(contentAspectRatioFromVideoTrack(track), closeTo(2.39, 1e-9));
    });

    test('returns null when nothing usable is present', () {
      expect(contentAspectRatioFromVideoTrack(null), isNull);
      expect(contentAspectRatioFromVideoTrack(const VideoTrackInfo()), isNull);
      expect(contentAspectRatioFromVideoTrack(const VideoTrackInfo(width: 0, height: 1080)), isNull);
    });
  });

  group('contentAspectRatioForFile', () {
    test('reads first video track for the matching file id', () {
      final detail = WatchDetail(
        contentId: 'ep-1',
        type: 'episode',
        title: 'Severance',
        versions: [
          FileVersion(
            fileId: 10,
            videoTracks: const [VideoTrackInfo(width: 1920, height: 1080)],
          ),
          FileVersion(
            fileId: 42,
            videoTracks: const [VideoTrackInfo(width: 3840, height: 1606, aspectRatio: '2.39:1')],
          ),
        ],
      );
      expect(contentAspectRatioForFile(detail, 42), closeTo(3840 / 1606, 1e-9));
    });

    test('parses video_tracks from watch JSON', () {
      final detail = WatchDetail.fromJson({
        'content_id': 'ep-1',
        'type': 'episode',
        'title': 'Severance',
        'versions': [
          {
            'file_id': 7,
            'video_tracks': [
              {'width': 3840, 'height': 1606, 'aspect_ratio': '2.39:1'},
            ],
            'audio_tracks': [],
            'subtitle_tracks': [],
          },
        ],
      });
      expect(detail.versions.single.videoTracks.single.width, 3840);
      expect(contentAspectRatioForFile(detail, 7), closeTo(3840 / 1606, 1e-9));
    });
  });
}
