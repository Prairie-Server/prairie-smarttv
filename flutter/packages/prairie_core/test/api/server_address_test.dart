import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

Matcher _throwsSetup(String message, {bool isPortError = false}) => throwsA(
  isA<ServerSetupValidationException>()
      .having((e) => e.message, 'message', message)
      .having((e) => e.isPortError, 'isPortError', isPortError),
);

void main() {
  group('buildServerSetupCandidateUrls', () {
    test('Auto tries HTTPS, then HTTP, then port 8090 for a bare host', () {
      expect(buildServerSetupCandidateUrls('prairie.local'), [
        'https://prairie.local',
        'http://prairie.local',
        'http://prairie.local:8090',
      ]);
    });

    test('Auto with a typed port tries HTTPS then HTTP on that port only', () {
      expect(buildServerSetupCandidateUrls('192.168.1.20:32400'), [
        'https://192.168.1.20:32400',
        'http://192.168.1.20:32400',
      ]);
    });

    test('Auto with the Port field set uses it', () {
      expect(buildServerSetupCandidateUrls('prairie.local', port: ' 9000 '), [
        'https://prairie.local:9000',
        'http://prairie.local:9000',
      ]);
    });

    test('a port in the address wins over the Port field', () {
      expect(buildServerSetupCandidateUrls('prairie.local:7000', port: '9000'), [
        'https://prairie.local:7000',
        'http://prairie.local:7000',
      ]);
    });

    test('Auto keeps a typed scheme and adds no fallback', () {
      expect(buildServerSetupCandidateUrls('http://prairie.local'), ['http://prairie.local']);
      expect(buildServerSetupCandidateUrls('HTTPS://Prairie.Local/'), ['https://prairie.local']);
    });

    test('an explicit protocol overrides the typed scheme', () {
      expect(
        buildServerSetupCandidateUrls('https://prairie.local', scheme: ServerSetupScheme.http),
        ['http://prairie.local'],
      );
      expect(
        buildServerSetupCandidateUrls('prairie.local', scheme: ServerSetupScheme.https),
        ['https://prairie.local'],
      );
    });

    test('keeps a path, drops a trailing slash and query', () {
      expect(buildServerSetupCandidateUrls('https://example.com/prairie/?x=1'), ['https://example.com/prairie']);
    });

    test('brackets IPv6 hosts', () {
      expect(buildServerSetupCandidateUrls('[fe80::1]:8090'), ['https://[fe80::1]:8090', 'http://[fe80::1]:8090']);
      expect(buildServerSetupCandidateUrls('fe80::1', scheme: ServerSetupScheme.http), ['http://[fe80::1]']);
    });

    test('a blank address asks for a host', () {
      expect(() => buildServerSetupCandidateUrls('   '), _throwsSetup('Please enter a server host.'));
    });

    test('rejects addresses that are not one', () {
      for (final bad in ['ftp://host', 'user:pw@host', 'two words', 'host:abc', '://host', '[fe80::1']) {
        expect(() => buildServerSetupCandidateUrls(bad), _throwsSetup('Enter a valid server address.'), reason: bad);
      }
    });

    test('port errors are flagged so Advanced options can open', () {
      const message = 'Port must be a number between 1 and 65535.';
      expect(() => buildServerSetupCandidateUrls('host', port: '0'), _throwsSetup(message, isPortError: true));
      expect(() => buildServerSetupCandidateUrls('host', port: '65536'), _throwsSetup(message, isPortError: true));
      expect(() => buildServerSetupCandidateUrls('host', port: 'abc'), _throwsSetup(message, isPortError: true));
      // A typed :0 is rejected, not dropped.
      expect(() => buildServerSetupCandidateUrls('host:0'), _throwsSetup(message, isPortError: true));
    });
  });

  group('serverSetupUsesCleartext', () {
    test('flags HTTP only when it is certain', () {
      expect(serverSetupUsesCleartext('prairie.local'), isFalse);
      expect(serverSetupUsesCleartext('http://prairie.local'), isTrue);
      expect(serverSetupUsesCleartext('prairie.local', scheme: ServerSetupScheme.http), isTrue);
      expect(serverSetupUsesCleartext('http://prairie.local', scheme: ServerSetupScheme.https), isFalse);
      expect(serverSetupUsesCleartext(''), isFalse);
    });
  });
}
