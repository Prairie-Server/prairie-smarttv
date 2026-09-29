import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  test('parses native v2 system info', () {
    final info = NativeSystemInfo.fromJson({
      'server_version': '1.0.0-dev',
      'api_major': 2,
      'contract_digest': 'abc123',
      'links': {
        'openapi': '/api/v2/openapi.json',
        'capabilities': '/api/v2/capabilities',
        'identity': '/api/v2/system/identity',
      },
    });

    expect(info.serverVersion, '1.0.0-dev');
    expect(info.apiMajor, 2);
    expect(info.contractDigest, 'abc123');
    expect(info.openapiPath, '/api/v2/openapi.json');
  });

  test('parses native v2 setup status', () {
    final status = NativeSetupStatus.fromJson({
      'needs_setup': false,
      'wizard_completed': true,
    });

    expect(status.needsSetup, isFalse);
    expect(status.wizardCompleted, isTrue);
  });

  test('only 404 and 405 mean the native discovery route is unavailable', () {
    expect(isNativeApiUnavailable(ApiError('missing', 404)), isTrue);
    expect(isNativeApiUnavailable(ApiError('method', 405)), isTrue);
    expect(isNativeApiUnavailable(ApiError('unauthorized', 401)), isFalse);
    expect(isNativeApiUnavailable(StateError('network')), isFalse);
  });
}
