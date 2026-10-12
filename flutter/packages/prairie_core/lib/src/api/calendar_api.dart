import '../models/auth.dart';
import '../models/calendar_event.dart';
import 'api_client.dart';

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `GET /api/v2/calendar` for [days] local days from [from], flattened to a
/// single event list. The window starts a day early because the server
/// reckons days in UTC (no `timezone` sent) — [groupCalendarEvents] regroups
/// by the viewer's local day and drops anything before today.
Future<List<CalendarEvent>> fetchCalendar(
  ApiClient client,
  PrairieSession session, {
  required DateTime from,
  int days = 14,
}) async {
  final start = DateTime(from.year, from.month, from.day - 1);
  final end = DateTime(from.year, from.month, from.day + days - 1);
  final query = Uri(queryParameters: {'start': _ymd(start), 'end': _ymd(end)}).query;
  final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/calendar?$query');
  return [
    for (final day in (json['events'] as List<dynamic>? ?? []))
      for (final event in ((day as Map<String, dynamic>)['items'] as List<dynamic>? ?? []))
        CalendarEvent.fromJson(event as Map<String, dynamic>),
  ];
}
