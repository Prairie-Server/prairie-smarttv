import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/tv_capabilities.dart';

/// Platform apps override this with a probed [TvPlaybackCapabilities]
/// (Tizen via `device_info_plus_tizen`, webOS via its device_info plugin).
/// Defaults are conservative and omit AV1 — without a probe the server will
/// re-encode AV1 sources.
final tvCapabilitiesProvider = Provider<TvPlaybackCapabilities>(
  (ref) => TvPlaybackCapabilities.defaults,
);
