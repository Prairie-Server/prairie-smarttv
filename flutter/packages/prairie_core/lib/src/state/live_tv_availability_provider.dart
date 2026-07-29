import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../api/livetv_api.dart';
import '../models/live_tv_channel.dart';
import 'session_provider.dart';

/// Whether the connected server has any Live TV channels, gating the Live TV
/// shell tab. Mirrors the `liveTvProbe` effect in src/App.tsx (persistent
/// cross-session caching via `liveTvProbeCache.ts` isn't ported — this
/// re-probes once per session instead of persisting the last known result).
final liveTvAvailableProvider = FutureProvider<bool>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return false;
  try {
    final channels = await fetchLiveTvChannels(ref.read(apiClientProvider), session);
    return channels.isNotEmpty;
  } on ApiError {
    return false;
  } catch (_) {
    return false;
  }
});

/// (channel, currently-airing program) pairs for Home's "On now" rail.
/// Mirrors the `showOnNow` rail in HomeBrowseScreen.tsx.
class OnNowEntry {
  const OnNowEntry(this.channel, this.program);
  final LiveTvChannel channel;
  final LiveTvProgram? program;
}

final onNowLiveTvProvider = FutureProvider<List<OnNowEntry>>((ref) async {
  final available = await ref.watch(liveTvAvailableProvider.future);
  if (!available) return [];
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final client = ref.read(apiClientProvider);
  try {
    final channels = await fetchLiveTvChannels(client, session);
    if (channels.isEmpty) return [];
    final programs = await fetchLiveTvGuide(client, session, channels.map((c) => c.id).toList());
    final index = indexProgramsByChannel(programs);
    return channels.take(12).map((c) => OnNowEntry(c, currentProgramInIndex(index, c.id))).toList();
  } catch (_) {
    return [];
  }
});
