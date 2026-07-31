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

  group('probeAudioCodecSupport', () {
    test('includes aac/ac3/eac3 unconditionally, matching Moonfin/Samsung docs', () {
      // Matches Moonfin's testAc3Support/testEac3Support (deviceProfile.js):
      // unconditional true for every Tizen version, no per-year gating.
      expect(probeAudioCodecSupport(tizenVersion: 6.5), containsAll(['aac', 'ac3', 'eac3']));
      expect(probeAudioCodecSupport(tizenVersion: 7.0), containsAll(['aac', 'ac3', 'eac3']));
      expect(probeAudioCodecSupport(tizenVersion: 0), containsAll(['aac', 'ac3', 'eac3']));
    });

    test('never advertises dts or mp3', () {
      final codecs = probeAudioCodecSupport(tizenVersion: 9.0);
      expect(codecs, isNot(contains('dts')));
      expect(codecs, isNot(contains('mp3')));
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

    test('never advertises HLS transcode support — video_player_videohole cannot play it', () {
      final caps = buildTizenCapabilities(tizenVersion: 6.5, screenWidth: 3840, screenHeight: 2160);
      expect(caps.supportsHlsTranscode, isFalse);
    });

    test('codecsAudio matches probeAudioCodecSupport regardless of Tizen version', () {
      final caps2022 = buildTizenCapabilities(tizenVersion: 6.5, screenWidth: 3840, screenHeight: 2160);
      expect(caps2022.codecsAudio, containsAll(['aac', 'ac3', 'eac3']));

      final caps2023 = buildTizenCapabilities(tizenVersion: 7.0, screenWidth: 3840, screenHeight: 2160);
      expect(caps2023.codecsAudio, containsAll(['aac', 'ac3', 'eac3']));
    });

    test('treats logical 1080p Flutter surface as UHD on modern Tizen', () {
      final caps = buildTizenCapabilities(
        tizenVersion: 6.5,
        screenWidth: 1920,
        screenHeight: 1080,
        avplayAvailable: true,
      );
      expect(caps.maxResolution, '2160p');
    });

    test('uhd:false keeps screen probe when explicitly disabled', () {
      final caps = buildTizenCapabilities(
        tizenVersion: 6.5,
        screenWidth: 1920,
        screenHeight: 1080,
        avplayAvailable: true,
        uhd: false,
      );
      expect(caps.maxResolution, '1080p');
    });

    test('omits av1 below 5.5', () {
      final caps = buildTizenCapabilities(
        tizenVersion: 5.0,
        screenWidth: 1920,
        screenHeight: 1080,
        avplayAvailable: true,
        uhd: false,
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

  group('maxAudioChannels', () {
    test('buildTizenCapabilities defaults to 6 (5.1) without the 8K override', () {
      final caps = buildTizenCapabilities(tizenVersion: 6.5, screenWidth: 3840, screenHeight: 2160);
      expect(caps.maxAudioChannels, 6);
    });

    test('buildTizenCapabilities reports 8 when uhd8K is passed', () {
      final caps = buildTizenCapabilities(tizenVersion: 6.5, screenWidth: 7680, screenHeight: 4320, uhd8K: true);
      expect(caps.maxAudioChannels, 8);
    });

    test('applyAudioChannelOverride raises the cap to 8 when is8KPanel is set', () {
      final caps = applyAudioChannelOverride(TvPlaybackCapabilities.defaults, is8KPanel: true);
      expect(caps.maxAudioChannels, 8);
    });

    test('applyAudioChannelOverride leaves the cap alone when is8KPanel is false', () {
      final caps = applyAudioChannelOverride(TvPlaybackCapabilities.defaults);
      expect(caps.maxAudioChannels, TvPlaybackCapabilities.defaults.maxAudioChannels);
    });
  });

  group('needsHlsBootstrap', () {
    test('true for transcode only — remux and direct both play stream_url progressive', () {
      expect(needsHlsBootstrap('direct'), isFalse);
      expect(needsHlsBootstrap('remux'), isFalse);
      expect(needsHlsBootstrap('TRANSCODE'), isTrue);
      expect(needsHlsBootstrap(null), isFalse);
    });
  });

  group('buildPlaybackStartRequest', () {
    test('sends max_audio_channels, defaulting to 6', () {
      final body = buildPlaybackStartRequest(const BuildPlaybackStartInput(fileId: 1, profileId: 'p1'));
      expect(body['max_audio_channels'], 6);
    });

    test('sends the caller-provided max_audio_channels', () {
      final body = buildPlaybackStartRequest(
        const BuildPlaybackStartInput(fileId: 1, profileId: 'p1', maxAudioChannels: 8),
      );
      expect(body['max_audio_channels'], 8);
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

  group('initSegmentUrl', () {
    test('resolves the fMP4 init segment URI and carries query auth', () {
      expect(
        initSegmentUrl(
          'https://x/a.m3u8?token=1',
          '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:10.427,\nseg_00000.m4s\n',
        ),
        'https://x/init.mp4?token=1',
      );
    });

    test('returns null when the playlist has no #EXT-X-MAP (mpegts)', () {
      expect(initSegmentUrl('https://x/a.m3u8', '#EXTM3U\n#EXTINF:1,\nseg.ts\n'), isNull);
    });
  });

  group('resolveTargetResolution', () {
    test('never upscales past panel max', () {
      expect(resolveTargetResolution('2160p', '1080p'), '1080p');
      expect(resolveTargetResolution('720p', '2160p'), '720p');
    });
  });
}
