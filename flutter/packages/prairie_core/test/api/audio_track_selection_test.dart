import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('selectPlayableAudioTrack', () {
    // The Tizen test file (row 515): TrueHD 7.1 default beside an AC-3 5.1.
    const blurayRemux = [
      AudioTrackInfo(codec: 'truehd', channels: 8, language: 'eng', isDefault: true),
      AudioTrackInfo(codec: 'ac3', channels: 2, language: 'spa'),
      AudioTrackInfo(codec: 'ac3', channels: 6, language: 'eng'),
    ];

    test('picks the same-language decodable companion over the default', () {
      expect(selectPlayableAudioTrack(blurayRemux, const ['aac', 'ac3', 'eac3'], 6), 2);
    });

    test('keeps the server choice when the default is decodable', () {
      expect(selectPlayableAudioTrack(blurayRemux, const ['truehd', 'ac3'], 8), isNull);
    });

    test('returns null when nothing is decodable', () {
      expect(selectPlayableAudioTrack(blurayRemux, const ['aac'], 6), isNull);
    });

    test('prefers a track within the channel ceiling', () {
      const tracks = [
        AudioTrackInfo(codec: 'truehd', channels: 8, language: 'eng', isDefault: true),
        AudioTrackInfo(codec: 'eac3', channels: 8, language: 'eng'),
        AudioTrackInfo(codec: 'ac3', channels: 6, language: 'eng'),
      ];
      expect(selectPlayableAudioTrack(tracks, const ['ac3', 'eac3'], 6), 2);
    });
  });

  test('start body carries the audio index and the client-selection claim', () {
    final body = buildPlaybackStartRequest(
      const BuildPlaybackStartInput(fileId: 515, profileId: 'p', audioTrackIndex: 2),
    );
    expect(body['audio_track_index'], 2);
    final deliveries = (body['client_playback_context'] as Map)['deliveries'] as Map;
    expect((deliveries['original_http'] as Map)['validated_claims'], contains('client_selected_audio_track_v1'));
    expect((deliveries['progressive'] as Map)['validated_claims'], isEmpty);
    expect(buildPlaybackStartRequest(const BuildPlaybackStartInput(fileId: 1, profileId: 'p')).containsKey('audio_track_index'), isFalse);
  });

  group('matchNativeAudioTrack', () {
    // Who Framed Roger Rabbit (file 515): the player omits the TrueHD stream,
    // so source ordinal 2 (DD 5.1) is native index 1, and native index 2 is
    // a DD 2.0 commentary.
    const main51 = AudioTrackInfo(codec: 'ac3', channels: 6, language: 'en', bitrateKbps: 640);
    const native = <NativeAudioTrack>[
      (language: 'eng', channels: 8, bitrate: 0), // DTS-HD MA 7.1
      (language: 'eng', channels: 6, bitrate: 640000), // DD 5.1
      (language: 'eng', channels: 2, bitrate: 320000), // DD 2.0 commentary
      (language: 'eng', channels: 2, bitrate: 192000),
      (language: 'fre', channels: 6, bitrate: 1536000), // DTS 5.1
    ];

    test('matches by attributes when the player omits streams', () {
      expect(matchNativeAudioTrack(native, 2, track: main51, sourceTrackCount: 12), 1);
    });

    test('uses the ordinal when the player lists every stream', () {
      expect(matchNativeAudioTrack(native, 2, track: main51, sourceTrackCount: 5), 2);
    });

    test('returns null when no stream has the channel count', () {
      const mono = AudioTrackInfo(codec: 'ac3', channels: 1, language: 'es');
      expect(matchNativeAudioTrack(native, 11, track: mono, sourceTrackCount: 12), isNull);
    });
  });
}
