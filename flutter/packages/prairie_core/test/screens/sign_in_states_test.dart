import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

ServerEntry _entry(String url, {String username = '', String profileId = ''}) => ServerEntry(
  id: ServerRegistryStore.entryIdFromUrl(url),
  url: url,
  fetchedName: '',
  username: username,
  profileId: profileId,
  profileName: '',
  accessToken: '',
  profileToken: '',
  lastUsedAt: 1,
);

PrairieSession _session(String url) =>
    PrairieSession(serverUrl: url, accessToken: 't', username: 'jonah', profileId: 'p1');

void main() {
  group('sign-in wording (Apple TV, Android #754)', () {
    test('a renewed code says so for as long as it shows', () {
      expect(signInWaitingStatus(renewed: false), 'Waiting for approval');
      expect(signInWaitingStatus(renewed: true), 'New code. Waiting for approval.');
    });

    test('declined', () {
      expect(signInDeclinedStatus, 'Sign-in was declined.');
      expect(signInDeclinedLead, 'Show a new code to try again.');
    });

    test('a wrong password reads as Apple TV words it', () {
      expect(loginErrorMessage(ApiError('Unauthorized', 401)), 'Incorrect username or password.');
      expect(loginErrorMessage(ApiError('Bad login', 400, 'invalid_credentials')), 'Incorrect username or password.');
      expect(loginErrorMessage(ApiError('Too many attempts', 429, 'rate_limited')), 'Too many attempts');
    });
  });

  group('SignInCodeText', () {
    test('draws the code upper case with en spaces between groups', () {
      expect(SignInCodeText.display(' ab12 cd34 '), 'AB12 CD34');
      expect(SignInCodeText.display('4821-7730'), '4821-7730');
    });

    testWidgets('renders one line, no tiles', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox(width: 120, child: SignInCodeText('4821 7730')))),
      );
      expect(find.text('4821 7730'), findsOneWidget);
      expect(find.byType(FittedBox), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ServerRegistryStore.forgetIfNeverSignedIn (Android #759)', () {
    const url = 'https://new.example.com';
    final registry = ServerRegistry(
      activeServerId: ServerRegistryStore.entryIdFromUrl(url),
      entries: [_entry(url), _entry('https://home.example.com', username: 'jonah', profileId: 'p1')],
      scanCidrs: const [],
    );

    test('removes a server the TV never signed in to', () {
      final next = ServerRegistryStore.forgetIfNeverSignedIn(registry, url, null);
      expect(next, isNotNull);
      expect(next!.entries.map((e) => e.url), ['https://home.example.com']);
      expect(next.activeServerId, ServerRegistryStore.entryIdFromUrl('https://home.example.com'));
    });

    test('keeps a server signed in to before', () {
      expect(ServerRegistryStore.forgetIfNeverSignedIn(registry, 'https://home.example.com', null), isNull);
    });

    test('keeps a server the live session is for', () {
      expect(ServerRegistryStore.forgetIfNeverSignedIn(registry, url, _session(url)), isNull);
      expect(
        ServerRegistryStore.forgetIfNeverSignedIn(registry, url, _session('https://home.example.com')),
        isNotNull,
      );
    });

    test('does nothing for a server that was never saved', () {
      expect(ServerRegistryStore.forgetIfNeverSignedIn(registry, 'https://other.example.com', null), isNull);
    });
  });
}
