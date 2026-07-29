import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('probeAv1Support', () {
    test('advertises when systeminfo says yes', () {
      expect(probeAv1Support(tizenVersion: 6.5, systemInfoAv1: true), isTrue);
    });

    test('advertises from canPlayAv1 when systeminfo denies', () {
      expect(probeAv1Support(tizenVersion: 6.5, systemInfoAv1: false, canPlayAv1: true), isTrue);
    });

    test('stays off when both signals are negative', () {
      expect(probeAv1Support(tizenVersion: 6.5, systemInfoAv1: false, canPlayAv1: false), isFalse);
    });

    test('refuses panels older than Tizen 5.5', () {
      expect(probeAv1Support(tizenVersion: 5.0, systemInfoAv1: true, canPlayAv1: true), isFalse);
    });

    test('stays off when version is unknown', () {
      expect(probeAv1Support(tizenVersion: 0, canPlayAv1: true), isFalse);
    });
  });

  group('buildTizenCapabilities', () {
    test('includes av1 for Tizen 6.5 with AVPlay', () {
      final caps = buildTizenCapabilities(
        tizenVersion: 6.5,
        screenWidth: 3840,
        screenHeight: 2160,
        avplayAvailable: true,
      );
      expect(caps.codecsVideo, contains('av1'));
      expect(caps.codecsVideo, contains('hevc'));
      expect(caps.maxResolution, '2160p');
      expect(caps.containers, contains('mkv'));
    });

    test('omits av1 below 5.5', () {
      final caps = buildTizenCapabilities(
        tizenVersion: 5.0,
        screenWidth: 1920,
        screenHeight: 1080,
        avplayAvailable: true,
      );
      expect(caps.codecsVideo, isNot(contains('av1')));
    });
  });

  group('buildWebosCapabilities', () {
    test('includes av1 for webOS 6+ with native player', () {
      final caps = buildWebosCapabilities(
        webosVersion: 6.0,
        screenWidth: 3840,
        screenHeight: 2160,
        nativePlayerAvailable: true,
        hdr10: true,
        uhd: true,
      );
      expect(caps.codecsVideo, contains('av1'));
      expect(caps.codecsVideo, contains('hevc'));
      expect(caps.maxResolution, '2160p');
      expect(caps.hdr, isTrue);
      expect(caps.containers, contains('mkv'));
    });

    test('omits av1 below webOS 6', () {
      final caps = buildWebosCapabilities(
        webosVersion: 5.0,
        screenWidth: 1920,
        screenHeight: 1080,
        nativePlayerAvailable: true,
      );
      expect(caps.codecsVideo, isNot(contains('av1')));
      expect(caps.codecsVideo, contains('hevc'));
    });

    test('uhd flag forces 2160p when screen probe is small', () {
      final caps = buildWebosCapabilities(
        webosVersion: 7.0,
        screenWidth: 1920,
        screenHeight: 1080,
        uhd: true,
      );
      expect(caps.maxResolution, '2160p');
    });
  });

  group('applyAv1AdvertiseOverrides', () {
    test('force adds av1', () {
      final caps = applyAv1AdvertiseOverrides(TvPlaybackCapabilities.defaults, forceAv1: true);
      expect(caps.codecsVideo, contains('av1'));
    });

    test('disable strips av1', () {
      final base = TvPlaybackCapabilities.defaults.copyWith(codecsVideo: ['h264', 'hevc', 'av1']);
      final caps = applyAv1AdvertiseOverrides(base, disableAv1: true);
      expect(caps.codecsVideo, isNot(contains('av1')));
    });
  });

  group('needsHlsBootstrap', () {
    test('true for remux and transcode only', () {
      expect(needsHlsBootstrap('direct'), isFalse);
      expect(needsHlsBootstrap('remux'), isTrue);
      expect(needsHlsBootstrap('TRANSCODE'), isTrue);
      expect(needsHlsBootstrap(null), isFalse);
    });
  });

  group('buildTranscodeStartRequest', () {
    test('uses codec copy for remux', () {
      final body = buildTranscodeStartRequest(
        const TranscodeStartInput(sessionId: 's1', seekSeconds: 40, playMethod: 'remux'),
      );
      expect(body['target_codec_video'], 'copy');
      expect(body['target_codec_audio'], 'copy');
      expect(body['target_resolution'], '');
      expect(body['target_bitrate_kbps'], 0);
    });

    test('omits target video codec for transcode', () {
      final body = buildTranscodeStartRequest(
        const TranscodeStartInput(
          sessionId: 's1',
          seekSeconds: 0,
          playMethod: 'transcode',
          sourceResolution: '2160p',
          maxResolution: '1080p',
        ),
      );
      expect(body.containsKey('target_codec_video'), isFalse);
      expect(body['target_resolution'], '1080p');
      expect(body['target_codec_audio'], 'aac');
    });
  });

  group('firstMediaSegmentUrl', () {
    test('resolves relative segments and carries query auth', () {
      expect(
        firstMediaSegmentUrl('https://x/a.m3u8?token=1', '#EXTM3U\n#EXTINF:1,\nseg.ts\n'),
        'https://x/seg.ts?token=1',
      );
    });
  });

  group('resolveTargetResolution', () {
    test('never upscales past panel max', () {
      expect(resolveTargetResolution('2160p', '1080p'), '1080p');
      expect(resolveTargetResolution('720p', '2160p'), '720p');
    });
  });
}
