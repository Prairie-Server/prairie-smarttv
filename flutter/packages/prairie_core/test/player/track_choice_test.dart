import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  test('sameTrackLanguage matches codes, regions and names', () {
    expect(sameTrackLanguage('eng', 'en'), isTrue);
    expect(sameTrackLanguage('en-US', 'ENG'), isTrue);
    expect(sameTrackLanguage('English', 'eng'), isTrue);
    expect(sameTrackLanguage('eng', 'jpn'), isFalse);
    expect(sameTrackLanguage('', ''), isFalse);
    expect(sameTrackLanguage('eng', null), isFalse);
  });

  group('isUnplayableSubtitle', () {
    test("uses the server's flag when present", () {
      expect(isUnplayableSubtitle(const SubtitleTrackInfo(codec: 'subrip', unplayable: true)), isTrue);
      expect(isUnplayableSubtitle(const SubtitleTrackInfo(codec: '', unplayable: false)), isFalse);
    });

    test('without the flag, only an embedded track with no codec is unplayable', () {
      expect(isUnplayableSubtitle(const SubtitleTrackInfo(language: 'eng')), isTrue);
      expect(isUnplayableSubtitle(const SubtitleTrackInfo(language: 'eng', codec: ' ')), isTrue);
      expect(isUnplayableSubtitle(const SubtitleTrackInfo(language: 'eng', codec: 'subrip')), isFalse);
      expect(isUnplayableSubtitle(const SubtitleTrackInfo(language: 'eng', external: true)), isFalse);
    });

    test('parses the unplayable flag', () {
      final track = SubtitleTrackInfo.fromJson({'language': 'eng', 'unplayable': true});
      expect(track.unplayable, isTrue);
    });
  });

  group('resolveStartSubtitleLanguage', () {
    test('an explicit launch pick wins, Off included', () {
      expect(
        resolveStartSubtitleLanguage(launchChoice: '', preferenceMode: 'always', preferenceLanguage: 'eng', deviceLanguage: 'eng'),
        '',
      );
      expect(resolveStartSubtitleLanguage(launchChoice: 'spa', preferenceMode: 'off'), 'spa');
    });

    test('a remembered Off stays off, even with a device language', () {
      expect(resolveStartSubtitleLanguage(preferenceMode: 'off', preferenceLanguage: 'eng', deviceLanguage: 'eng'), '');
    });

    test('a remembered pick turns its language on', () {
      expect(resolveStartSubtitleLanguage(preferenceMode: 'always', preferenceLanguage: 'fre', deviceLanguage: 'eng'), 'fre');
    });

    test("this TV's own setting comes next", () {
      expect(resolveStartSubtitleLanguage(preferenceMode: 'auto', preferenceLanguage: 'eng', deviceLanguage: 'spa'), 'spa');
      expect(resolveStartSubtitleLanguage(deviceLanguage: 'spa'), 'spa');
    });

    test('Auto shows subtitles only for audio in another language, else none', () {
      expect(resolveStartSubtitleLanguage(preferenceMode: 'auto', preferenceLanguage: 'eng', audioLanguage: 'jpn'), 'eng');
      expect(resolveStartSubtitleLanguage(preferenceMode: 'auto', preferenceLanguage: 'eng', audioLanguage: 'en'), '');
      expect(resolveStartSubtitleLanguage(preferenceMode: 'auto', preferenceLanguage: ''), '');
      expect(resolveStartSubtitleLanguage(), '');
    });

    test('never auto-picks a language the server can only list as unplayable', () {
      const broken = [SubtitleTrackInfo(language: 'eng', codec: '')];
      const mixed = [SubtitleTrackInfo(language: 'eng', codec: ''), SubtitleTrackInfo(language: 'en', codec: 'subrip')];
      expect(resolveStartSubtitleLanguage(deviceLanguage: 'eng', serverTracks: broken), '');
      expect(resolveStartSubtitleLanguage(deviceLanguage: 'eng', serverTracks: mixed), 'eng');
      // No server track in the language at all: left to the player.
      expect(resolveStartSubtitleLanguage(deviceLanguage: 'spa', serverTracks: broken), 'spa');
    });
  });

  test('matchServerSubtitleTrack prefers a showable, non-forced track', () {
    const tracks = [
      SubtitleTrackInfo(language: 'eng', codec: ''),
      SubtitleTrackInfo(language: 'eng', codec: 'subrip', forced: true),
      SubtitleTrackInfo(language: 'eng', codec: 'subrip'),
      SubtitleTrackInfo(language: 'spa', codec: 'subrip', forced: true),
    ];
    expect(matchServerSubtitleTrack(tracks, 'en'), 2);
    expect(matchServerSubtitleTrack(tracks, 'spa'), 3);
    expect(matchServerSubtitleTrack(tracks, 'jpn'), isNull);
  });

  group('resolveStartAudioTrackIndex', () {
    const tracks = [
      AudioTrackInfo(language: 'eng', isDefault: true),
      AudioTrackInfo(language: 'jpn'),
    ];

    test('launch pick, then a remembered non-default track, then the fallback', () {
      expect(resolveStartAudioTrackIndex(launchIndex: 0, effectiveIndex: 1, tracks: tracks, playableFallback: 1), 0);
      expect(resolveStartAudioTrackIndex(effectiveIndex: 1, tracks: tracks), 1);
      expect(resolveStartAudioTrackIndex(effectiveIndex: 0, tracks: tracks, playableFallback: 1), 1);
      expect(resolveStartAudioTrackIndex(effectiveIndex: 0, tracks: tracks), isNull);
      expect(resolveStartAudioTrackIndex(effectiveIndex: 5, tracks: tracks), isNull);
    });
  });

  group('remembered-choice bodies', () {
    test('a subtitle pick is always-on in its language and never pins forced subtitles', () {
      final body = subtitlePreferenceBody(
        track: const SubtitleTrackInfo(index: 3, language: 'eng', codec: 'subrip', title: 'English (SDH)', forced: false, hearingImpaired: true),
      );
      expect(body['subtitle_track_index'], 3);
      expect(body['subtitle_language'], 'eng');
      expect(body['subtitle_mode'], 'always');
      expect(body.containsKey('show_forced_subtitles'), isFalse);
      expect(body['track_signature'], {
        'language': 'eng',
        'codec': 'subrip',
        'label': 'English (SDH)',
        'forced': false,
        'hearing_impaired': true,
        'source': 'embedded',
      });
    });

    test('Off is index -1 with mode off', () {
      expect(subtitlePreferenceBody(), {'subtitle_track_index': -1, 'subtitle_language': '', 'subtitle_mode': 'off'});
    });

    test('a native-only pick keeps its language and ordinal', () {
      final body = subtitlePreferenceBody(language: 'jpn', trackIndex: 1);
      expect(body['subtitle_track_index'], 1);
      expect(body['subtitle_mode'], 'always');
      expect(body['track_signature'], {'language': 'jpn'});
      expect(body.containsKey('show_forced_subtitles'), isFalse);
    });

    test('an audio pick carries its index, language and signature', () {
      final body = audioPreferenceBody(1, const AudioTrackInfo(language: 'jpn', codec: 'aac', channels: 2, isDefault: false));
      expect(body, {
        'audio_track_index': 1,
        'audio_language': 'jpn',
        'track_signature': {'language': 'jpn', 'codec': 'aac', 'channels': 2, 'default': false},
      });
    });
  });

  test('watch detail carries the effective subtitle and audio choices', () {
    final watch = WatchDetail.fromJson({
      'content_id': 'e1',
      'type': 'episode',
      'title': 'Pilot',
      'effective_subtitle_mode': 'off',
      'effective_subtitle_language': 'eng',
      'versions': [
        {'file_id': '7', 'effective_audio_track_index': 1},
      ],
    });
    expect(watch.effectiveSubtitleMode, 'off');
    expect(watch.effectiveSubtitleLanguage, 'eng');
    expect(watch.versions.single.effectiveAudioTrackIndex, 1);
  });
}
