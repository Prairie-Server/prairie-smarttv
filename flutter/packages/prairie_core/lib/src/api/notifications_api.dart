import '../models/app_notification.dart';
import '../models/auth.dart';
import 'api_client.dart';

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

/// Mirrors `listNotifications` from the web app's src/api/v2/notifications.ts.
// ponytail: first page only (newest 50); follow `page.next_cursor` if a TV
// inbox ever needs to scroll further back.
Future<NotificationPage> fetchNotifications(ApiClient client, PrairieSession session, {int limit = 50}) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/notifications?status=all&limit=$limit',
  );
  return NotificationPage.fromJson(json);
}

/// Mirrors `unreadNotificationCount` from src/api/v2/notifications.ts.
Future<int> fetchNotificationUnreadCount(ApiClient client, PrairieSession session) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/notifications/unread-count',
  );
  return (json['count'] as num?)?.toInt() ?? 0;
}

Future<void> markNotificationRead(ApiClient client, PrairieSession session, String id) => client.request<dynamic>(
  _sessionOptions(session),
  '/api/v2/notifications/${Uri.encodeComponent(id)}/read',
  method: 'POST',
);

/// Marks everything up to [through] (a page's `read_cutoff`) read.
Future<void> markAllNotificationsRead(ApiClient client, PrairieSession session, String through) => client
    .request<dynamic>(
      _sessionOptions(session),
      '/api/v2/notifications/read-all',
      method: 'POST',
      body: {'through': through},
    );
