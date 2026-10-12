import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  test('sanitizeDiagnosticEvent fits the server event charset and length', () {
    expect(sanitizeDiagnosticEvent('init.ok:1080p_hls-2'), 'init.ok:1080p_hls-2');
    expect(sanitizeDiagnosticEvent('error: Not supported / x=1'), 'error:_Not_supported___x_1');
    expect(sanitizeDiagnosticEvent('a' * 100), hasLength(64));
    expect(sanitizeDiagnosticEvent('   '), 'unknown');
    for (final raw in ['é ü 🎬', 'seek?pos=12&x', 'a' * 65]) {
      expect(RegExp(r'^[A-Za-z0-9_.:\-]{1,64}$').hasMatch(sanitizeDiagnosticEvent(raw)), isTrue, reason: raw);
    }
  });
}
