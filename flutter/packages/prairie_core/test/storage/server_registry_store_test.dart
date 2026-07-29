import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesAsync prefs;
  late DurableStore durable;
  late ServerRegistryStore store;

  setUp(() async {
    installInMemorySharedPreferences();
    prefs = SharedPreferencesAsync();
    durable = DurableStore(prefs: prefs);
    store = ServerRegistryStore(prefs: prefs, durable: durable);
  });

  group('ServerRegistryStore', () {
    test('derives stable ids and round-trips the registry without tokens', () async {
      final id = ServerRegistryStore.entryIdFromUrl(' https://prairie.example.com/// ');
      expect(id, isNotEmpty);
      expect(id, ServerRegistryStore.entryIdFromUrl('https://prairie.example.com'));
      expect(ServerRegistryStore.entryIdFromUrl(''), '');

      final registry = ServerRegistryStore.addOrUpdate(
        const ServerRegistry(activeServerId: '', entries: [], scanCidrs: ['10.0.0.0/24']),
        ServerEntry(
          id: '',
          url: 'https://prairie.example.com',
          fetchedName: 'Prairie',
          username: 'jonah',
          profileId: 'p1',
          profileName: '',
          accessToken: 'tok',
          profileToken: 'pt',
          lastUsedAt: 0,
        ),
      );
      await store.save(registry);
      final loaded = await store.load();
      expect(loaded.entries, hasLength(1));
      expect(loaded.entries.first.fetchedName, 'Prairie');
      expect(loaded.entries.first.accessToken, '');
      expect(loaded.entries.first.profileToken, '');
      expect(ServerRegistryStore.displayName(loaded.entries.first), 'Prairie');
      expect(
        ServerRegistryStore.displayName(
          const ServerEntry(
            id: 'x',
            url: 'https://x.example',
            fetchedName: '',
            username: '',
            profileId: '',
            profileName: '',
            accessToken: '',
            profileToken: '',
            lastUsedAt: 0,
          ),
        ),
        'https://x.example',
      );
      expect(loaded.scanCidrs, ['10.0.0.0/24']);
    });

    test('switches active server and sorts with active first', () {
      var registry = ServerRegistryStore.addOrUpdate(
        ServerRegistry.empty(),
        const ServerEntry(
          id: '',
          url: 'https://a.example.com',
          fetchedName: '',
          username: 'u',
          profileId: 'p',
          profileName: 'Primary',
          accessToken: 't1',
          profileToken: 'pt',
          lastUsedAt: 10,
        ),
      );
      registry = ServerRegistryStore.addOrUpdate(
        registry,
        const ServerEntry(
          id: '',
          url: 'https://b.example.com',
          fetchedName: '',
          username: 'u',
          profileId: 'p',
          profileName: '',
          accessToken: 't2',
          profileToken: '',
          lastUsedAt: 20,
        ),
      );
      final idB = ServerRegistryStore.entryIdFromUrl('https://b.example.com');
      registry = ServerRegistryStore.switchTo(registry, idB);
      expect(registry.activeServerId, idB);
      final session = ServerRegistryStore.sessionFromEntry(registry.entries.firstWhere((e) => e.id == idB));
      expect(session?.serverUrl, 'https://b.example.com');
      expect(session?.accessToken, 't2');
      expect(ServerRegistryStore.sortedEntries(registry).first.id, idB);
      expect(
        ServerRegistryStore.sessionFromEntry(
          const ServerEntry(
            id: 'x',
            url: 'https://x',
            fetchedName: '',
            username: '',
            profileId: '',
            profileName: '',
            accessToken: '',
            profileToken: '',
            lastUsedAt: 0,
          ),
        ),
        isNull,
      );
    });

    test('removeServer reassigns active id', () {
      var registry = ServerRegistryStore.addOrUpdate(
        ServerRegistry.empty(),
        const ServerEntry(
          id: '',
          url: 'https://a.example.com',
          fetchedName: 'A',
          username: 'u',
          profileId: 'p',
          profileName: '',
          accessToken: '',
          profileToken: '',
          lastUsedAt: 1,
        ),
      );
      registry = ServerRegistryStore.addOrUpdate(
        registry,
        const ServerEntry(
          id: '',
          url: 'https://b.example.com',
          fetchedName: 'B',
          username: 'u',
          profileId: 'p',
          profileName: '',
          accessToken: '',
          profileToken: '',
          lastUsedAt: 2,
        ),
      );
      final idA = ServerRegistryStore.entryIdFromUrl('https://a.example.com');
      final idB = ServerRegistryStore.entryIdFromUrl('https://b.example.com');
      registry = ServerRegistry(
        activeServerId: idA,
        entries: registry.entries,
        scanCidrs: registry.scanCidrs,
      );
      registry = ServerRegistryStore.removeServer(registry, idA);
      expect(registry.entries, hasLength(1));
      expect(registry.activeServerId, idB);
    });

    test('rememberSession sets active id from session URL', () {
      final session = const PrairieSession(
        serverUrl: 'https://prairie.example.com/',
        accessToken: 'tok',
        username: 'jonah',
        profileId: 'p1',
        profileName: 'Primary',
        profileToken: 'pt',
      );
      final next = ServerRegistryStore.rememberSession(ServerRegistry.empty(), session, fetchedName: 'Living Room');
      expect(next.activeServerId, ServerRegistryStore.entryIdFromUrl('https://prairie.example.com'));
      expect(next.entries.first.fetchedName, 'Living Room');
      expect(next.entries.first.username, 'jonah');
    });

    test('migrateFromLegacy promotes lastServerUrl into registry', () async {
      await durable.saveLastServerUrl('https://legacy.example.com');
      final migrated = await store.migrateFromLegacy();
      expect(migrated.entries, hasLength(1));
      expect(migrated.entries.first.url, 'https://legacy.example.com');
      expect(migrated.activeServerId, ServerRegistryStore.entryIdFromUrl('https://legacy.example.com'));

      // Second call is a no-op when entries already exist.
      await durable.saveLastServerUrl('https://other.example.com');
      final again = await store.migrateFromLegacy();
      expect(again.entries, hasLength(1));
      expect(again.entries.first.url, 'https://legacy.example.com');
    });

    test('load purges legacy token material from prefs', () async {
      final id = ServerRegistryStore.entryIdFromUrl('https://prairie.example.com');
      await prefs.setString(
        DurableStore.serverRegistryKey,
        jsonEncode({
          'activeServerId': id,
          'entries': [
            {
              'id': id,
              'url': 'https://prairie.example.com',
              'fetchedName': 'Prairie',
              'username': 'u',
              'profileId': 'p',
              'profileName': '',
              'accessToken': 'secret',
              'profileToken': 'psecret',
              'lastUsedAt': 1,
            },
          ],
          'scanCidrs': <String>[],
        }),
      );
      final loaded = await store.load();
      expect(loaded.entries.first.accessToken, '');
      final raw = await prefs.getString(DurableStore.serverRegistryKey);
      expect(raw!.contains('secret'), isFalse);
    });
  });

  group('DurableStore', () {
    test('ensureStorageSchema records version and migrates playback key', () async {
      await prefs.setString(DurableStore.legacyPlaybackSettingsKey, '{"forceDirectPlay":true}');
      final version = await durable.ensureStorageSchema();
      expect(version, DurableStore.storageSchemaVersion);
      expect(await prefs.getString(DurableStore.storageSchemaKey), '2');
      expect(await prefs.getString(DurableStore.playbackSettingsKey), '{"forceDirectPlay":true}');
    });

    test('lastServerUrl survives normalize', () async {
      await durable.saveLastServerUrl(' https://prairie.example.com/// ');
      expect(await durable.loadLastServerUrl(), 'https://prairie.example.com');
    });
  });
}
