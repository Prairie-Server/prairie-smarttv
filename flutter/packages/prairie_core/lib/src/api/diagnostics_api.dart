import '../models/auth.dart';
import 'api_client.dart';

final _disallowedEventChars = RegExp(r'[^A-Za-z0-9_.:\-]');

/// Coerces a free-form diagnostic string into the server's `event` charset:
/// 1-64 characters of `[A-Za-z0-9_.:-]` (anything else would 422). Other
/// characters become `_`; an empty result becomes `unknown`.
String sanitizeDiagnosticEvent(String raw) {
  var event = raw.trim().replaceAll(_disallowedEventChars, '_');
  if (event.length > 64) event = event.substring(0, 64);
  return event.isEmpty ? 'unknown' : event;
}

/// Fire-and-forget `POST /api/v2/diagnostics/client-events` (202). Sent with
/// session options so auth, profile and `X-Prairie-Device-Id` go out. Never
/// retried and never throws: a lost or rejected batch (incl. 429) is dropped,
/// and diagnostics must never affect playback.
Future<void> sendClientDiagnosticEvent(ApiClient client, PrairieSession session, String event, {DateTime? occurredAt}) async {
  try {
    await client.request<dynamic>(
      ApiClientOptions(
        serverUrl: session.serverUrl,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        profileId: session.profileId,
        profileToken: session.profileToken,
      ),
      '/api/v2/diagnostics/client-events',
      method: 'POST',
      body: {
        'events': [
          {'event': sanitizeDiagnosticEvent(event), 'occurred_at': (occurredAt ?? DateTime.now()).toUtc().toIso8601String()},
        ],
      },
    );
  } catch (_) {
    // Diagnostics must never affect playback.
  }
}
