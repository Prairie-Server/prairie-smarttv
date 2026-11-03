import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installInMemorySharedPreferences);

  group('Profile Selection (Android #762)', () {
    test('a new TV is offered, and keeps opening the profile automatically', () async {
      final saved = await loadProfileLaunchBehavior(SharedPreferencesAsync());
      expect(saved, isNull);
      expect(offersRememberProfile(saved), isTrue);
      expect(showsWhoIsWatchingAtLaunch(saved), isFalse);
    });

    test('Ask Every Time shows Who\'s Watching at launch and is not offered again', () async {
      final prefs = SharedPreferencesAsync();
      await saveProfileLaunchBehavior(prefs, ProfileLaunchBehavior.askEveryLaunch);
      final saved = await loadProfileLaunchBehavior(prefs);
      expect(saved, ProfileLaunchBehavior.askEveryLaunch);
      expect(offersRememberProfile(saved), isFalse);
      expect(showsWhoIsWatchingAtLaunch(saved), isTrue);
    });

    test('Remember opens the profile at launch', () async {
      final prefs = SharedPreferencesAsync();
      await saveProfileLaunchBehavior(prefs, ProfileLaunchBehavior.automatic);
      final saved = await loadProfileLaunchBehavior(prefs);
      expect(saved, ProfileLaunchBehavior.automatic);
      expect(showsWhoIsWatchingAtLaunch(saved), isFalse);
    });

    test('an unknown stored value reads as unanswered', () async {
      installInMemorySharedPreferences({profileLaunchBehaviorKey: 'sometimes'});
      expect(await loadProfileLaunchBehavior(SharedPreferencesAsync()), isNull);
    });

    test('the key survives updates', () {
      expect(DurableStore.preservedStorageKeys, contains(profileLaunchBehaviorKey));
    });

    test("Apple TV's wording", () {
      expect(rememberProfileOfferTitle('Jonah'), 'Open Jonah automatically?');
      expect(rememberProfileOfferTitle('  '), 'Open this profile automatically?');
      expect(rememberProfileOfferMessage, startsWith("Prairie can skip Who's Watching"));
    });
  });
}
