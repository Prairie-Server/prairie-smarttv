import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/src/screens/player_screen.dart';

void main() {
  test('seek bar step is a fixed 10s, not a runtime percentage', () {
    // Guard against regressing to Material Slider's default 5% jumps.
    expect(playerSeekBarStep, const Duration(seconds: 10));
  });

  test('seek preview is centered on the thumb whatever its width, and stays on the bar', () {
    // Mid-bar: a narrow timecode and a wide trickplay tile share one center.
    expect(seekPreviewLeft(1000, 70, 0.5, 18) + 35, 500);
    expect(seekPreviewLeft(1000, 176, 0.5, 18) + 88, 500);
    // The thumb rides the inset track, not the full width.
    expect(seekPreviewLeft(1000, 70, 0.25, 18) + 35, 18 + 964 * 0.25);
    // Clamped at either end instead of hanging off the bar.
    expect(seekPreviewLeft(1000, 176, 0, 18), 0);
    expect(seekPreviewLeft(1000, 176, 1, 18), 1000 - 176);
  });

  test('holding Left/Right grows the seek step, starting from the fixed step', () {
    expect(playerSeekHoldStep(Duration.zero), playerSeekBarStep);
    expect(playerSeekHoldStep(const Duration(milliseconds: 999)), playerSeekBarStep);
    expect(playerSeekHoldStep(const Duration(seconds: 1)), const Duration(seconds: 30));
    expect(playerSeekHoldStep(const Duration(seconds: 3)), const Duration(minutes: 1));
    expect(playerSeekHoldStep(const Duration(seconds: 6)), const Duration(minutes: 2));
    expect(playerSeekHoldStep(const Duration(minutes: 5)), const Duration(minutes: 2));
  });

  testWidgets('idle focus catcher can receive D-pad after chrome is gone', (tester) async {
    var showCount = 0;
    final idle = FocusNode(debugLabel: 'test.idle');
    addTearDown(idle.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: idle,
          autofocus: true,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.goBack ||
                event.logicalKey == LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            }
            showCount++;
            return KeyEventResult.handled;
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(idle.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(showCount, 1);

    // Back must remain free for PopScope / exit.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(showCount, 1);
  });
}
