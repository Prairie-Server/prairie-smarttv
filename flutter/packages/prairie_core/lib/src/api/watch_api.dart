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

/// Mirrors `formatSubtitleLabel`.
String formatSubtitleLabel({String? language, String? label, String? title, bool? hearingImpaired, bool? forced}) {
  final base = label ?? title ?? language ?? 'Subtitle';
  final tags = [if (forced ?? false) 'Forced', if (hearingImpaired ?? false) 'HI'];
  return tags.isNotEmpty ? '$base (${tags.join(', ')})' : base;
}
