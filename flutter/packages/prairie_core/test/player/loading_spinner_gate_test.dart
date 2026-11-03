import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  final t0 = DateTime(2026, 11, 3, 20);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('a wait shorter than 500 ms never shows the spinner', () {
    final gate = LoadingSpinnerGate();
    expect(gate.update(waiting: true, now: at(0)), isFalse);
    expect(gate.update(waiting: true, now: at(499)), isFalse);
    expect(gate.update(waiting: false, now: at(450)), isFalse);
    expect(gate.nextChangeIn(at(450)), isNull);
  });

  test('shows after 500 ms of waiting and stays at least 500 ms', () {
    final gate = LoadingSpinnerGate();
    gate.update(waiting: true, now: at(0));
    expect(gate.nextChangeIn(at(100)), const Duration(milliseconds: 400));
    expect(gate.update(waiting: true, now: at(500)), isTrue);
    expect(gate.nextChangeIn(at(500)), isNull);
    // The wait ends 100 ms after the spinner appeared: it holds 400 ms more.
    expect(gate.update(waiting: false, now: at(600)), isTrue);
    expect(gate.nextChangeIn(at(600)), const Duration(milliseconds: 400));
    expect(gate.update(waiting: false, now: at(999)), isTrue);
    expect(gate.update(waiting: false, now: at(1000)), isFalse);
  });

  test('a long wait hides as soon as it ends past the minimum', () {
    final gate = LoadingSpinnerGate();
    gate.update(waiting: true, now: at(0));
    gate.update(waiting: true, now: at(700));
    expect(gate.update(waiting: false, now: at(3000)), isFalse);
  });

  test('a new wait during the minimum keeps it up without restarting the delay', () {
    final gate = LoadingSpinnerGate();
    gate.update(waiting: true, now: at(0));
    gate.update(waiting: true, now: at(500));
    gate.update(waiting: false, now: at(700));
    expect(gate.update(waiting: true, now: at(800)), isTrue);
    expect(gate.update(waiting: true, now: at(2000)), isTrue);
  });

  test('the delay restarts for a wait after the spinner went away', () {
    final gate = LoadingSpinnerGate();
    gate.update(waiting: true, now: at(0));
    gate.update(waiting: true, now: at(500));
    gate.update(waiting: false, now: at(1200));
    expect(gate.update(waiting: true, now: at(1300)), isFalse);
    expect(gate.update(waiting: true, now: at(1799)), isFalse);
    expect(gate.update(waiting: true, now: at(1800)), isTrue);
  });
}
