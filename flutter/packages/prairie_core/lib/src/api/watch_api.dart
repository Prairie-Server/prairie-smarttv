import 'package:prairie_core/src/lib/language_labels.dart';

import '../models/auth.dart';
import '../models/watch_detail.dart';
import 'api_client.dart';

/// Mirrors `fetchWatchDetail` from src/api/watch.ts.
Future<WatchDetail> fetchWatchDetail(ApiClient client, PrairieSession session, String contentId) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(
      serverUrl: session.serverUrl,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      profileId: session.profileId,
      profileToken: session.profileToken,
    ),
    '/api/v1/watch/${Uri.encodeComponent(contentId)}',
  );
  return WatchDetail.fromJson(json);
}

/// Picks a playable file_id from watch detail (preferred -> last -> first
/// version). Mirrors `selectPlaybackFileId`.
int? selectPlaybackFileId(WatchDetail watch, {int? preferredFileId}) {
  if (watch.versions.isEmpty) return null;
  if (preferredFileId != null &&
      preferredFileId > 0 &&
      watch.versions.any((v) => v.fileId == preferredFileId)) {
    return preferredFileId;
  }
  final last = watch.userData?.lastFileId;
  if (last != null && last > 0 && watch.versions.any((v) => v.fileId == last)) {
    return last;
  }
  return watch.versions.first.fileId;
}

/// Mirrors `selectFileVersion`.
FileVersion? selectFileVersion(WatchDetail watch, int fileId) {
  for (final v in watch.versions) {
    if (v.fileId == fileId) return v;
  }
  return null;
}

/// Mirrors `formatAudioLabel`, with the language segment humanized for
/// display (the TS original showed the raw track metadata verbatim).
String formatAudioLabel(AudioTrackInfo track, int index) {
  final parts = [
    if (track.language != null && track.language!.isNotEmpty) humanizeTrackLanguage(track.language!),
    track.title ?? track.embeddedTitle,
    track.codec,
    if (track.channels != null) '${track.channels}ch',
  ].whereType<String>().toList();
  return parts.isNotEmpty ? parts.join(' · ') : 'Audio ${index + 1}';
}

/// Formats a subtitle track for pickers. Prefers a human language name over
/// raw titles like `SDH` or codec identifiers like `HDMV_PGS_SUBTITLE`.
///
/// Examples:
/// - language `en`, title `SDH` → `English (SDH)`
/// - language `eng`, hearingImpaired → `English (HI)`
/// - language `spa`, title `Commentary` → `Spanish · Commentary`
String formatSubtitleLabel({
  String? language,
  String? label,
  String? title,
  bool? hearingImpaired,
  bool? forced,
  bool? external,
  int? index,
}) {
  String? usefulLanguage;
  if (language != null && language.trim().isNotEmpty) {
    final humanized = humanizeTrackLanguage(language);
    if (humanized != 'Unknown') usefulLanguage = humanized;
  }

  final rawTitle = usefulTrackLabel(label) ?? usefulTrackLabel(title);
  var titleIsTag = rawTitle != null && isAccessibilityTitleTag(rawTitle);
  var descriptiveTitle = rawTitle != null && !titleIsTag ? rawTitle : null;
  String? titleTag = titleIsTag ? rawTitle : null;

  // "Spanish SDH" with language Spanish → keep Spanish as base, SDH as a tag.
  if (descriptiveTitle != null && usefulLanguage != null && _titleRedundantWithLanguage(descriptiveTitle, usefulLanguage)) {
    final remainder = descriptiveTitle.substring(usefulLanguage.length).trim();
    if (remainder.isNotEmpty && isAccessibilityTitleTag(remainder)) {
      titleTag = remainder;
      titleIsTag = true;
    }
    descriptiveTitle = null;
  }

  late final String base;
  if (usefulLanguage != null) {
    if (descriptiveTitle != null) {
      base = '$usefulLanguage · $descriptiveTitle';
    } else {
      base = usefulLanguage;
    }
  } else if (descriptiveTitle != null) {
    base = descriptiveTitle;
  } else {
    base = index != null ? 'Subtitle ${index + 1}' : 'Subtitle';
  }

  final tags = <String>[
    if (forced ?? false) 'Forced',
    if (hearingImpaired ?? false) 'HI',
    if (titleTag != null) _normalizeAccessibilityTag(titleTag),
    if (external ?? false) 'External',
  ];
  // Dedupe while preserving order (title "HI" + hearingImpaired flag).
  final uniqueTags = <String>[];
  for (final tag in tags) {
    if (!uniqueTags.contains(tag)) uniqueTags.add(tag);
  }
  return uniqueTags.isNotEmpty ? '$base (${uniqueTags.join(', ')})' : base;
}

bool _titleRedundantWithLanguage(String title, String language) {
  final lower = title.toLowerCase();
  final lang = language.toLowerCase();
  return lower == lang || lower.startsWith('$lang ');
}

String _normalizeAccessibilityTag(String raw) {
  final lower = raw.trim().toLowerCase();
  return switch (lower) {
    'sdh' => 'SDH',
    'hi' => 'HI',
    'cc' => 'CC',
    'forced' || 'forced narrative' => 'Forced',
    _ => raw.trim()[0].toUpperCase() + raw.trim().substring(1).toLowerCase(),
  };
}

/// Formats a server [SubtitleTrackInfo] for pickers — language first,
/// numbered fallback when metadata is missing or codec-like.
String formatSubtitleTrackLabel(SubtitleTrackInfo track, int index) {
  return formatSubtitleLabel(
    language: track.language,
    title: track.title,
    hearingImpaired: track.hearingImpaired,
    forced: track.forced,
    external: track.external,
    index: index,
  );
}
