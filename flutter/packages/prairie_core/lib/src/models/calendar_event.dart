/// One airing or release from `GET /api/v2/calendar` (`CalendarEvent` in the
/// v2 contract).
class CalendarEvent {
  const CalendarEvent({
    required this.contentId,
    required this.type,
    required this.title,
    required this.airDate,
    required this.localAirDate,
    this.airAt,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.posterUrl,
    this.watched = false,
  });

  final String contentId;

  /// `movie`, `episode`, or `season_premiere`.
  final String type;

  /// The movie or series title.
  final String title;

  /// The source air date, YYYY-MM-DD.
  final String airDate;

  /// The air date in the zone the server reckoned days in, YYYY-MM-DD.
  final String localAirDate;

  /// The airing as an instant, when the network's time and zone are known.
  final DateTime? airAt;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final String? posterUrl;
  final bool watched;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    contentId: json['content_id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    airDate: json['air_date'] as String,
    localAirDate: json['local_air_date'] as String,
    airAt: DateTime.tryParse(json['air_at'] as String? ?? ''),
    seriesId: json['series_id'] as String?,
    seasonNumber: json['season_number'] as int?,
    episodeNumber: json['episode_number'] as int?,
    episodeTitle: json['episode_title'] as String?,
    posterUrl: json['poster_url'] as String?,
    watched: json['watched'] as bool? ?? false,
  );

  /// The item the detail screen should open: episodes and premieres go to
  /// their series (matching the web's CalendarEventCard), movies to themselves.
  String get detailContentId => type == 'movie' ? contentId : (seriesId ?? contentId);

  /// `S02E01 · Episode title`, or whichever parts are known.
  String? get episodeLabel {
    final s = seasonNumber, e = episodeNumber;
    final code = s != null && e != null
        ? 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}'
        : null;
    final parts = [?code, if (episodeTitle?.isNotEmpty ?? false) episodeTitle!];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// The viewer's local calendar day this event belongs on. The TV has no
  /// IANA zone name to send the server, so days come back in UTC; regroup by
  /// the exact instant when known, else by the source air date.
  DateTime get localDay {
    final at = airAt?.toLocal();
    if (at != null) return DateTime(at.year, at.month, at.day);
    return DateTime.parse(airDate);
  }
}

/// A day heading and the events airing on it.
class CalendarDay {
  const CalendarDay({required this.day, required this.label, required this.events});

  final DateTime day;
  final String label;
  final List<CalendarEvent> events;
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today", "Tomorrow", or e.g. "Friday, Oct 16".
String calendarDayLabel(DateTime day, DateTime today) {
  final diff = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return '${_weekdays[day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}';
}

/// Groups [events] by local day, oldest first, keeping only the [days] local
/// days from [now] — the UTC fetch window spills a day either side.
/// Within a day, events keep the server's order.
List<CalendarDay> groupCalendarEvents(List<CalendarEvent> events, DateTime now, {int days = 14}) {
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(today.year, today.month, today.day + days);
  final byDay = <DateTime, List<CalendarEvent>>{};
  for (final event in events) {
    final day = event.localDay;
    if (day.isBefore(today) || !day.isBefore(end)) continue;
    byDay.putIfAbsent(day, () => []).add(event);
  }
  final keys = byDay.keys.toList()..sort();
  return [
    for (final day in keys) CalendarDay(day: day, label: calendarDayLabel(day, today), events: byDay[day]!),
  ];
}
