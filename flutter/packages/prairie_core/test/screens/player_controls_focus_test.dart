import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/src/screens/player_screen.dart';

void main() {
  test('seek bar step is a fixed 10s, not a runtime percentage', () {
    // Guard against regressing to Material Slider's default 5% jumps.
    expect(playerSeekBarStep, const Duration(seconds: 10));
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
