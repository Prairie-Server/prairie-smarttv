import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('humanizeTrackLanguage', () {
    test('maps ISO 639-1 and 639-2 codes to English names', () {
      expect(humanizeTrackLanguage('en'), 'English');
      expect(humanizeTrackLanguage('eng'), 'English');
      expect(humanizeTrackLanguage('en-US'), 'English');
      expect(humanizeTrackLanguage('es'), 'Spanish');
      expect(humanizeTrackLanguage('spa'), 'Spanish');
      expect(humanizeTrackLanguage('ja'), 'Japanese');
    });
  });

  group('formatSubtitleLabel', () {
    test('prefers a real language over a codec-like title', () {
      expect(
        formatSubtitleLabel(language: 'eng', title: 'HDMV_PGS_SUBTITLE', index: 0),
        'English',
      );
    });

    test('shows the language name for two-letter codes, not the raw identifier', () {
      expect(formatSubtitleLabel(language: 'en', index: 0), 'English');
      expect(formatSubtitleLabel(language: 'en', title: 'SDH', index: 0), 'English (SDH)');
    });

    test('treats accessibility-only titles as tags on the language', () {
      expect(
        formatSubtitleLabel(language: 'eng', title: 'SDH', hearingImpaired: true),
        'English (HI, SDH)',
      );
      expect(formatSubtitleLabel(language: 'fra', title: 'Forced'), 'French (Forced)');
    });

    test('rejects codec-like titles and languages for a numbered fallback', () {
      expect(
        formatSubtitleLabel(language: 'hdmv_pgs_subtitle', title: 'HDMV_PGS_SUBTITLE', index: 1),
        'Subtitle 2',
      );
      expect(
        formatSubtitleLabel(title: 'S_HDMV/PGS', index: 0),
        'Subtitle 1',
      );
    });

    test('keeps descriptive titles beside the language', () {
      expect(
        formatSubtitleLabel(language: 'spa', title: 'Commentary'),
        'Spanish · Commentary',
      );
      expect(
        formatSubtitleLabel(language: 'fra', forced: true),
        'French (Forced)',
      );
    });
  });

  group('formatSubtitleTrackLabel', () {
    test('formats a server track without exposing codec identifiers', () {
      const track = SubtitleTrackInfo(
        language: 'en',
        title: 'HDMV_PGS_SUBTITLE',
        hearingImpaired: true,
      );
      expect(formatSubtitleTrackLabel(track, 0), 'English (HI)');
    });
  });

  group('looksLikeCodecLabel', () {
    test('detects common image-subtitle codec strings', () {
      expect(looksLikeCodecLabel('HDMV_PGS_SUBTITLE'), isTrue);
      expect(looksLikeCodecLabel('S_HDMV/PGS'), isTrue);
      expect(looksLikeCodecLabel('English'), isFalse);
      expect(looksLikeCodecLabel('eng'), isFalse);
      expect(looksLikeCodecLabel('en'), isFalse);
    });
  });
}
