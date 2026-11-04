import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/src/api/requests_api.dart';
import 'package:prairie_core/src/state/session_provider.dart';

/// Whether media requests are on for the acting profile, gating the profile
/// menu's Requests row and Search's "Available to request" row. Read once
/// per server and profile; the requests screens re-check on open and on
/// resume, and invalidate this when they find requests turned off.
final requestsAvailableProvider = FutureProvider<bool>((ref) async {
  final key = ref.watch(sessionProvider.select((s) => s == null ? null : (s.serverUrl, s.profileId)));
  if (key == null) return false;
  try {
    return (await fetchRequestsStatus(ref.read(apiClientProvider), ref.read(sessionProvider)!)).available;
  } catch (_) {
    return false;
  }
});
