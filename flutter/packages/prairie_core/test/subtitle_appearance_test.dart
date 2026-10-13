import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  test('Shadow style adds a blurred drop shadow; None adds nothing', () {
    const none = SubtitleAppearance(textOutline: false);
    expect(subtitleAppearanceTextStyle(none).shadows, isNull);

    final shadows = subtitleAppearanceTextStyle(none.copyWith(backgroundStyle: SubtitleBackgroundStyle.shadow)).shadows!;
    expect(shadows, hasLength(1));
    expect(shadows.single.blurRadius, greaterThan(0));
  });
}
