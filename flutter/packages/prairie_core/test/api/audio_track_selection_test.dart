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
}
