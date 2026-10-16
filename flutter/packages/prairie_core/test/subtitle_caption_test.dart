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

    test('converts ASS uppercase N line-break escapes', () {
      final caption = SubtitleCaption.parse(r'First\\NSecond');

      expect(caption?.text, 'First\\nSecond');
    });

    test('converts lowercase n line-break escapes', () {
      final caption = SubtitleCaption.parse(r'First\\nSecond');

      expect(caption?.text, 'First\\nSecond');
    });

    test('converts line breaks while removing ASS alignment tags', () {
      final caption = SubtitleCaption.parse(r'{\\an8}First\\NSecond');

      expect(caption?.text, 'First\\nSecond');
      expect(caption?.verticalPosition, SubtitleVerticalPosition.top);
    });

    test('preserves ordinary brace text', () {
      expect(SubtitleCaption.parse('Use {settings}'), isNotNull);
      expect(SubtitleCaption.parse('Use {settings}')?.text, 'Use {settings}');
    });
  });
}
