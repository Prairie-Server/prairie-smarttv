import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Install an in-memory [SharedPreferencesAsync] backend for widget/unit tests.
void installInMemorySharedPreferences([Map<String, Object>? seed]) {
  SharedPreferencesAsyncPlatform.instance =
      seed == null || seed.isEmpty
          ? InMemorySharedPreferencesAsync.empty()
          : InMemorySharedPreferencesAsync.withData(Map<String, Object>.from(seed));
}
