import 'package:shared_preferences/shared_preferences.dart';

import '../storage/durable_store.dart';

/// Whether the TV opens the last profile at launch or shows Who's Watching.
/// Mirrors prairie-apple's `ProfileLaunchBehavior` (the untimed cases).
enum ProfileLaunchBehavior {
  /// Open the last profile picked on this TV (the behavior before the
  /// setting existed, so an unanswered TV keeps it).
  automatic('automatic', 'Automatic', 'Open the last profile picked on this TV when Prairie starts.'),

  /// Show Who's Watching every time Prairie starts.
  askEveryLaunch('askEveryLaunch', 'Every Time', "Show Who's Watching whenever Prairie starts.");

  const ProfileLaunchBehavior(this.storageValue, this.title, this.description);

  final String storageValue;
  final String title;
  final String description;

  static ProfileLaunchBehavior? parse(String? raw) {
    for (final b in values) {
      if (b.storageValue == raw) return b;
    }
    return null;
  }
}

/// SharedPreferences key; absent until the first-sign-in offer is answered.
const profileLaunchBehaviorKey = DurableStore.profileLaunchBehaviorKey;

/// The saved answer, or null when this TV hasn't been asked yet.
Future<ProfileLaunchBehavior?> loadProfileLaunchBehavior(SharedPreferencesAsync prefs) async {
  try {
    return ProfileLaunchBehavior.parse(await prefs.getString(profileLaunchBehaviorKey));
  } catch (_) {
    return null;
  }
}

/// Throws when the answer can't be saved, so the offer can stay open.
Future<void> saveProfileLaunchBehavior(SharedPreferencesAsync prefs, ProfileLaunchBehavior behavior) =>
    prefs.setString(profileLaunchBehaviorKey, behavior.storageValue);

/// A new TV (no answer saved) offers to open the first profile picked
/// automatically (Android #762).
bool offersRememberProfile(ProfileLaunchBehavior? saved) => saved == null;

/// Launch shows Who's Watching instead of reopening the saved profile.
bool showsWhoIsWatchingAtLaunch(ProfileLaunchBehavior? saved) => saved == ProfileLaunchBehavior.askEveryLaunch;

/// Apple TV's alert title for the offer.
String rememberProfileOfferTitle(String profileName) {
  final name = profileName.trim();
  return 'Open ${name.isEmpty ? 'this profile' : name} automatically?';
}

const rememberProfileOfferMessage =
    "Prairie can skip Who's Watching and open this profile when it starts on this TV. "
    'You can change this later in Settings > Servers > Profile Selection.';
