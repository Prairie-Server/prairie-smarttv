import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('SubtitleCaption.parse', () {
    test('preserves top alignment from ASS \\an8', () {
      final caption = SubtitleCaption.parse(r'{\an8}Hello');

      expect(caption?.text, 'Hello');
      expect(caption?.verticalPosition, SubtitleVerticalPosition.top);
    });

    test('maps ASS middle and bottom alignments', () {
      expect(
        SubtitleCaption.parse(r'{\an5}Hello')?.verticalPosition,
        SubtitleVerticalPosition.middle,
      );
      expect(
        SubtitleCaption.parse(r'{\an2}Hello')?.verticalPosition,
        SubtitleVerticalPosition.bottom,
      );
    });

    test('removes override blocks and retains readable cue text', () {
      final caption = SubtitleCaption.parse(r'{\an8\i1} Hello {\i0}');

      expect(caption?.text, 'Hello');
      expect(caption?.verticalPosition, SubtitleVerticalPosition.top);
    });

    test('returns null for empty or tag-only cues', () {
      expect(SubtitleCaption.parse('   '), isNull);
      expect(SubtitleCaption.parse(r'{\an8}'), isNull);
    });

    test('preserves ordinary brace text', () {
      expect(SubtitleCaption.parse('Use {settings}'), isNotNull);
      expect(SubtitleCaption.parse('Use {settings}')?.text, 'Use {settings}');
    });
  });
}
