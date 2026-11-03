import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/libraries_api.dart';
import '../models/library.dart';
import 'session_provider.dart';

/// The acting profile's libraries, read once per server and profile. Gates
/// the library-type top-bar tabs and backs their library lists. A failed
/// read yields no libraries (the tabs stay hidden) rather than an error.
final librariesProvider = FutureProvider<List<Library>>((ref) async {
  // Keyed on server + profile only, so a token refresh doesn't re-read.
  final key = ref.watch(sessionProvider.select((s) => s == null ? null : (s.serverUrl, s.profileId)));
  if (key == null) return const [];
  try {
    return await fetchLibraries(ref.read(apiClientProvider), ref.read(sessionProvider)!);
  } catch (_) {
    return const [];
  }
});
