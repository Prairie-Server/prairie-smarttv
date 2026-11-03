import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

const _url = 'https://home.example.com';

ServerEntry _entry(String url, {String name = ''}) => ServerEntry(
  id: ServerRegistryStore.entryIdFromUrl(url),
  url: url,
  fetchedName: name,
  username: 'jonah',
  profileId: 'p1',
  profileName: 'Jonah',
  accessToken: '',
  profileToken: '',
  lastUsedAt: 1,
);

const _session = PrairieSession(serverUrl: _url, accessToken: 't', username: 'jonah', profileId: 'p1');

class _Fake {
  _Fake({this.failSave = false, this.failClear = false});

  final bool failSave;
  final bool failClear;
  ServerRegistry registry = ServerRegistry(
    activeServerId: ServerRegistryStore.entryIdFromUrl(_url),
    entries: [_entry(_url, name: 'Home'), _entry('https://cabin.example.com')],
    scanCidrs: const [],
  );
  bool cleared = false;
  final List<String> calls = [];
  Completer<void>? clearGate;

  Future<ServerRegistry> load() async => registry;

  Future<void> save(ServerRegistry next) async {
    calls.add('save');
    if (failSave) throw StateError('disk full');
    registry = next;
  }

  Future<void> clear() async {
    calls.add('clear');
    await clearGate?.future;
    if (failClear) throw StateError('secure storage');
    cleared = true;
  }
}

Future<SignOutResult?> _run(SignOutRunner runner, _Fake fake, {required bool removeServer, PrairieSession? session = _session}) =>
    runner.run(
      removeServer: removeServer,
      session: session,
      loadRegistry: fake.load,
      saveRegistry: fake.save,
      clearSession: fake.clear,
    );

void main() {
  group('SignOutRunner (Android #764)', () {
    test('Sign Out keeps the server and leads to its sign-in', () async {
      final fake = _Fake();
      final result = await _run(SignOutRunner(), fake, removeServer: false);
      expect(result, isA<SignedOut>());
      final signedOut = result! as SignedOut;
      expect(signedOut.removedServer, isFalse);
      expect(signedOut.serverUrl, _url);
      expect(signedOut.serverName, 'Home');
      expect(signedOut.username, 'jonah');
      expect(signedOut.notice, isNull);
      expect(fake.cleared, isTrue);
      expect(fake.registry.entries, hasLength(2));
    });

    test('Sign Out & Remove Server forgets the server before clearing the session', () async {
      final fake = _Fake();
      final result = await _run(SignOutRunner(), fake, removeServer: true) as SignedOut;
      expect(result.removedServer, isTrue);
      expect(fake.calls, ['save', 'clear']);
      expect(fake.registry.entries.map((e) => e.url), ['https://cabin.example.com']);
    });

    test('a removal that cannot be saved still signs out, with an error', () async {
      final fake = _Fake(failSave: true);
      final result = await _run(SignOutRunner(), fake, removeServer: true) as SignedOut;
      expect(result.removedServer, isFalse);
      expect(result.notice, "Prairie couldn't remove the saved server. Please try again.");
      expect(fake.cleared, isTrue);
    });

    test('a local clear failure refuses', () async {
      final result = await _run(SignOutRunner(), _Fake(failClear: true), removeServer: false);
      expect((result! as SignOutRefused).message, signOutLocalFailedMessage);
    });

    test('no session refuses', () async {
      final result = await _run(SignOutRunner(), _Fake(), removeServer: false, session: null);
      expect((result! as SignOutRefused).message, signOutSessionChangedMessage);
    });

    test('a second request while one runs is ignored', () async {
      final runner = SignOutRunner();
      final fake = _Fake()..clearGate = Completer<void>();
      final first = _run(runner, fake, removeServer: false);
      await Future<void>.delayed(Duration.zero);
      expect(runner.running, isTrue);
      expect(await _run(runner, fake, removeServer: true), isNull);
      fake.clearGate!.complete();
      expect(await first, isA<SignedOut>());
      expect(runner.running, isFalse);
      expect(fake.calls, ['clear']);
    });
  });
}
