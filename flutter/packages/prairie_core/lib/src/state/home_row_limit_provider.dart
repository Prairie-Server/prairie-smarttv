import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/home_api.dart';
import 'session_provider.dart';

/// The `item_limit` Home's section list carries for this server (see
/// [sectionItemLimitFor]), read from `GET /api/v2/home/capabilities` once
/// per server. A failed or slow read counts as unsupported: no limit is sent.
final sectionItemLimitProvider = FutureProvider<int?>((ref) async {
  final serverUrl = ref.watch(sessionProvider.select((s) => s?.serverUrl));
  if (serverUrl == null) return null;
  try {
    final max = await fetchSectionItemLimitMax(ref.read(apiClientProvider), ref.read(sessionProvider)!)
        .timeout(const Duration(seconds: 3));
    return sectionItemLimitFor(max);
  } catch (_) {
    return null;
  }
});
