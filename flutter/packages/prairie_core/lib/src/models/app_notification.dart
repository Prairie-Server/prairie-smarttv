/// One row of the acting profile's notification inbox. Mirrors
/// `AppNotification` from the web app's src/api/v2/notifications.ts; the
/// title/description fallbacks mirror pages/Notifications.tsx.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    this.readAt,
    this.seriesId,
    this.seriesTitle,
    this.episodeId,
    this.episodeTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.reasonFlags = const {},
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final flags = json['reason_flags'];
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      readAt: DateTime.tryParse(json['read_at'] as String? ?? ''),
      seriesId: json['series_id'] as String?,
      seriesTitle: json['series_title'] as String?,
      episodeId: json['episode_id'] as String?,
      episodeTitle: json['episode_title'] as String?,
      seasonNumber: (json['season_number'] as num?)?.toInt(),
      episodeNumber: (json['episode_number'] as num?)?.toInt(),
      reasonFlags: flags is Map<String, dynamic> ? flags : const {},
    );
  }

  final String id;
  final String type;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? seriesId;
  final String? seriesTitle;
  final String? episodeId;
  final String? episodeTitle;
  final int? seasonNumber;
  final int? episodeNumber;

  /// Free-form per-type payload (`title`, `media_type`, `reason`, ...).
  final Map<String, dynamic> reasonFlags;

  bool get unread => readAt == null;

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    type: type,
    createdAt: createdAt,
    readAt: readAt ?? at,
    seriesId: seriesId,
    seriesTitle: seriesTitle,
    episodeId: episodeId,
    episodeTitle: episodeTitle,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    reasonFlags: reasonFlags,
  );

  /// The catalog item the row opens, if any. Approved/declined requests
  /// point at a TMDB title with no catalog item yet, so they open nothing.
  String? get contentId => episodeId ?? seriesId;

  String? _flag(String key) => reasonFlags[key] is String ? reasonFlags[key] as String : null;

  String get title => switch (type) {
    'episode.available' => _nonEmpty(seriesTitle) ?? 'New episode available',
    'request.fulfilled' => _nonEmpty(seriesTitle) ?? 'Request available',
    'request.approved' || 'request.declined' => _nonEmpty(_flag('title')) ?? 'Media request',
    // Unknown types get a generic title — the type registry is extensible.
    _ => 'Notification',
  };

  String get description {
    switch (type) {
      case 'episode.available':
        final code = seasonNumber != null && episodeNumber != null
            ? 'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}'
            : null;
        return _nonEmpty([code, _nonEmpty(episodeTitle)].whereType<String>().join(' — ')) ?? 'New episode available';
      case 'request.fulfilled':
        final noun = switch (_flag('media_type')) {
          'movie' => 'movie',
          'series' => 'series',
          _ => null,
        };
        if (reasonFlags['follower'] == true) {
          return 'A ${noun ?? 'title'} you followed is now available';
        }
        return noun != null ? 'Your requested $noun is now available' : 'Your request is now available';
      case 'request.approved':
        return 'Your request was approved';
      case 'request.declined':
        final reason = _nonEmpty(_flag('reason'));
        return reason != null ? 'Your request was declined — $reason' : 'Your request was declined';
      default:
        return type;
    }
  }
}

String? _nonEmpty(String? value) => value == null || value.isEmpty ? null : value;

/// First page of `GET /api/v2/notifications`.
class NotificationPage {
  const NotificationPage({required this.items, required this.readCutoff});

  factory NotificationPage.fromJson(Map<String, dynamic> json) => NotificationPage(
    items: [
      for (final row in (json['items'] as List<dynamic>? ?? []))
        AppNotification.fromJson(row as Map<String, dynamic>),
    ],
    readCutoff: json['read_cutoff'] as String? ?? '',
  );

  final List<AppNotification> items;

  /// Opaque watermark for `read-all`'s `through`, so "Mark all read" never
  /// covers notifications that arrived after this page was fetched.
  final String readCutoff;
}
