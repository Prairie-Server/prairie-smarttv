import 'dart:async';

import '../models/auth.dart';
import 'api_client.dart';

/// One rung of the server's transcode ladder.
///
/// Key selection on [id] — never on [label] or [height]. High variants share a
/// height and differ only by bitrate (`1080p-high` vs `1080p`).
class QualityLadderRung {
  const QualityLadderRung({
    required this.id,
    required this.label,
    required this.resolution,
    required this.height,
    required this.bitrateKbps,
  });

  final String id;
  final String label;
  final String resolution;
  final int height;
  final int bitrateKbps;

  factory QualityLadderRung.fromJson(Map<String, dynamic> json) => QualityLadderRung(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    resolution: json['resolution'] as String? ?? '',
    height: (json['height'] as num?)?.toInt() ?? 0,
    bitrateKbps: (json['bitrate_kbps'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'resolution': resolution,
    'height': height,
    'bitrate_kbps': bitrateKbps,
  };
}

/// Picker payload from `GET /api/v1/playback/quality-ladder`.
class QualityLadderResponse {
  const QualityLadderResponse({
    required this.rungs,
    required this.modes,
    this.sourceHeight,
  });

  final List<QualityLadderRung> rungs;
  final List<String> modes;
  final int? sourceHeight;

  factory QualityLadderResponse.fromJson(Map<String, dynamic> json) => QualityLadderResponse(
    rungs: (json['rungs'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => QualityLadderRung.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    modes: (json['modes'] as List<dynamic>? ?? []).whereType<String>().toList(),
    sourceHeight: (json['source_height'] as num?)?.toInt(),
  );
}

/// One row in the quality menu. [id] is a mode (`auto`/`original`) or a rung id.
class QualityOption {
  const QualityOption({
    required this.id,
    required this.label,
    this.sublabel = '',
    this.resolution = '',
    this.bitrateKbps = 0,
    this.isOriginal = false,
    this.isAuto = false,
  });

  final String id;
  final String label;
  final String sublabel;
  final String resolution;
  final int bitrateKbps;
  final bool isOriginal;
  final bool isAuto;
}

/// Fallback ladder, used only when the server cannot be reached.
///
/// Mirrors `internal/playback/quality_ladder.go` and web's `FALLBACK_LADDER`.
/// Deliberately the *only* copy of these numbers left in the Flutter client —
/// live values come from the server so adaptive advice can never name a rung
/// the menu cannot select.
const fallbackQualityLadder = <QualityLadderRung>[
  QualityLadderRung(id: '2160p', label: '4K', resolution: '2160p', height: 2160, bitrateKbps: 20000),
  QualityLadderRung(id: '1080p-high', label: '1080p High', resolution: '1080p', height: 1080, bitrateKbps: 10000),
  QualityLadderRung(id: '1080p', label: '1080p', resolution: '1080p', height: 1080, bitrateKbps: 6000),
  QualityLadderRung(id: '720p-high', label: '720p High', resolution: '720p', height: 720, bitrateKbps: 4000),
  QualityLadderRung(id: '720p', label: '720p', resolution: '720p', height: 720, bitrateKbps: 2000),
  QualityLadderRung(id: '480p', label: '480p', resolution: '480p', height: 480, bitrateKbps: 1500),
  QualityLadderRung(id: '420p', label: '420p', resolution: '420p', height: 420, bitrateKbps: 720),
];

const defaultQualityModes = <String>['auto', 'original'];

/// Module-level cache: the ladder is server configuration, not per-session.
List<QualityLadderRung>? _cachedLadder;
Future<List<QualityLadderRung>>? _inFlight;

/// True when every rung is fully populated. All-or-nothing: a partially valid
/// response means the contract shifted, and silently serving survivors would
/// hide that while handing the viewer a truncated menu.
bool isValidQualityLadder(List<QualityLadderRung>? rungs) {
  if (rungs == null || rungs.isEmpty) return false;
  for (final rung in rungs) {
    if (rung.id.isEmpty ||
        rung.label.isEmpty ||
        rung.resolution.isEmpty ||
        rung.height <= 0 ||
        rung.bitrateKbps <= 0) {
      return false;
    }
  }
  return true;
}

/// Caps a ladder to rungs the source can actually offer (highest first).
///
/// Mirrors `QualityLadderFor`: omit upscales; keep a small +8 tolerance for
/// sources mastered slightly off a rung; never return empty.
List<QualityLadderRung> qualityLadderForSourceHeight(
  List<QualityLadderRung> ladder,
  int sourceHeight,
) {
  if (sourceHeight <= 0) return List<QualityLadderRung>.from(ladder);
  final out = ladder.where((rung) => rung.height <= sourceHeight + 8).toList();
  if (out.isEmpty) return [ladder.last];
  return out;
}

/// Test seam: clears the module-level cache between cases.
void resetQualityLadderCache() {
  _cachedLadder = null;
  _inFlight = null;
}

Future<List<QualityLadderRung>> _loadLadder(ApiClient client, PrairieSession session) {
  if (_cachedLadder != null) return Future.value(_cachedLadder);
  return _inFlight ??= () async {
    try {
      final json = await client.request<Map<String, dynamic>>(
        ApiClientOptions(
          serverUrl: session.serverUrl,
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          profileId: session.profileId,
          profileToken: session.profileToken,
        ),
        // Full ladder is server configuration and cached process-wide. Callers
        // that want a source-capped menu pass sourceHeight to [fetchQualityLadder]
        // (or hit `?source_height=` themselves); we filter locally so a 1080p
        // session cannot pin a truncated cache for a later 4K file.
        '/api/v1/playback/quality-ladder',
        method: 'GET',
      );
      final resp = QualityLadderResponse.fromJson(json);
      // An empty or malformed ladder is a failure, and failures are not cached:
      // caching the fallback here would make every later mount skip the server
      // for the rest of the process lifetime.
      if (!isValidQualityLadder(resp.rungs)) return fallbackQualityLadder;
      _cachedLadder = resp.rungs;
      return resp.rungs;
    } catch (_) {
      // Do not cache a failure — a transient error should not pin the fallback.
      return fallbackQualityLadder;
    } finally {
      _inFlight = null;
    }
  }();
}

/// The server's transcode ladder, highest rung first.
///
/// Returns the fallback synchronously via [cachedOrFallbackQualityLadder] so
/// the quality menu is never empty, then resolves with the server's ladder
/// once loaded. Pass [sourceHeight] to cap the same way `?source_height=` does
/// server-side.
Future<List<QualityLadderRung>> fetchQualityLadder(
  ApiClient client,
  PrairieSession session, {
  int sourceHeight = 0,
}) async {
  final ladder = await _loadLadder(client, session);
  return qualityLadderForSourceHeight(ladder, sourceHeight);
}

/// Synchronous snapshot for first paint — cached server ladder or fallback.
List<QualityLadderRung> cachedOrFallbackQualityLadder({int sourceHeight = 0}) {
  return qualityLadderForSourceHeight(_cachedLadder ?? fallbackQualityLadder, sourceHeight);
}

/// Prefetch the ladder so the first quality-menu open is instant.
void prefetchQualityLadder(ApiClient client, PrairieSession session) {
  unawaited(_loadLadder(client, session));
}

String formatQualityBitrate(int kbps) {
  if (kbps >= 1000) {
    final mbps = kbps / 1000;
    return mbps % 1 == 0 ? '${mbps.toInt()} Mbps' : '${mbps.toStringAsFixed(1)} Mbps';
  }
  return '$kbps kbps';
}

/// Numeric height for a resolution token, preferring the live ladder.
int resolveNativeHeight(String resolution, List<QualityLadderRung> ladder) {
  final needle = resolution.trim().toLowerCase();
  for (final rung in ladder) {
    if (rung.resolution.toLowerCase() == needle && rung.height > 0) {
      return rung.height;
    }
  }

  switch (needle) {
    case '2160p':
    case '4k':
    case 'uhd':
      return 2160;
    case '1440p':
      return 1440;
    case '1080p':
    case 'fhd':
      return 1080;
    case '720p':
    case 'hd':
      return 720;
    case '480p':
    case 'sd':
      return 480;
    case '420p':
      return 420;
  }
  final parsed = int.tryParse(needle.replaceFirst(RegExp(r'p$'), ''));
  return (parsed != null && parsed > 0) ? parsed : 0;
}

/// Source height for a watch file: probe height first, then resolution token.
int sourceHeightForFile({
  required List<QualityLadderRung> ladder,
  String? resolution,
  int? probedHeight,
}) {
  if (probedHeight != null && probedHeight > 0) return probedHeight;
  if (resolution == null || resolution.trim().isEmpty) return 0;
  return resolveNativeHeight(resolution, ladder);
}

String _playMethodLabel(String? playMethod) {
  switch ((playMethod ?? '').trim().toLowerCase()) {
    case 'direct':
      return 'Direct Play';
    case 'remux':
      return 'Remux';
    case 'transcode':
      return 'Transcode';
    default:
      return '';
  }
}

/// Builds the quality menu: modes (`auto`, `original`) first, then rungs
/// strictly below native height (Original already covers source resolution).
List<QualityOption> buildQualityOptions({
  required List<QualityLadderRung> ladder,
  required int nativeHeight,
  String? playMethod,
  String? sourceResolutionLabel,
  int sourceBitrateKbps = 0,
  List<String> modes = defaultQualityModes,
}) {
  final options = <QualityOption>[];
  final orderedModes = modes.isEmpty ? defaultQualityModes : modes;

  for (final mode in orderedModes) {
    final id = mode.trim().toLowerCase();
    if (id == 'auto') {
      options.add(const QualityOption(id: 'auto', label: 'Auto', isAuto: true));
      continue;
    }
    if (id == 'original' || id == 'source' || id == 'max') {
      final res = (sourceResolutionLabel ?? '').trim();
      final displayRes = res == '2160p' ? '4K' : (res.isEmpty ? 'Original' : res);
      final methodLabel = _playMethodLabel(playMethod);
      final bitrateLabel = sourceBitrateKbps > 0 ? formatQualityBitrate(sourceBitrateKbps) : '';
      final sublabel = [methodLabel, bitrateLabel].where((s) => s.isNotEmpty).join(' · ');
      options.add(
        QualityOption(
          id: 'original',
          label: res.isEmpty ? 'Original' : 'Original ($displayRes)',
          sublabel: sublabel,
          isOriginal: true,
        ),
      );
    }
  }

  if (nativeHeight <= 0) {
    for (final tier in ladder) {
      options.add(
        QualityOption(
          id: tier.id,
          label: tier.label,
          sublabel: '~${formatQualityBitrate(tier.bitrateKbps)}',
          resolution: tier.resolution,
          bitrateKbps: tier.bitrateKbps,
        ),
      );
    }
    return options;
  }

  for (final tier in ladder) {
    // Rungs at or above native are omitted: "Original" already covers playing
    // at source resolution, and an upscale would spend encode time on detail
    // the file does not contain.
    if (tier.height >= nativeHeight) continue;
    options.add(
      QualityOption(
        id: tier.id,
        label: tier.label,
        sublabel: '~${formatQualityBitrate(tier.bitrateKbps)}',
        resolution: tier.resolution,
        bitrateKbps: tier.bitrateKbps,
      ),
    );
  }
  return options;
}

/// Picks the best rung at or below [maxHeight] for Auto starts.
QualityLadderRung? bestAutoRung(List<QualityLadderRung> ladder, int maxHeight) {
  if (ladder.isEmpty) return null;
  if (maxHeight <= 0) return ladder.first;
  for (final rung in ladder) {
    if (rung.height <= maxHeight + 8) return rung;
  }
  return ladder.last;
}

/// Resolves a quality menu id to the transcode targets to send.
///
/// Returns null for `original` on a direct-play base (caller should drop HLS).
({String resolution, int bitrateKbps, bool copyVideo})? resolveQualityTargets({
  required String qualityId,
  required List<QualityOption> options,
  required String? playMethod,
  required List<QualityLadderRung> ladder,
  int deviceMaxHeight = 0,
}) {
  final id = qualityId.trim().toLowerCase();
  if (id == 'original') {
    final method = (playMethod ?? '').trim().toLowerCase();
    if (method == 'direct') return null;
    if (method == 'remux') {
      return (resolution: '', bitrateKbps: 0, copyVideo: true);
    }
    // Transcode base still encodes at source — leave resolution empty so the
    // server keeps source scale, bitrate from the top offerable rung.
    final top = bestAutoRung(ladder, deviceMaxHeight);
    return (
      resolution: '',
      bitrateKbps: top?.bitrateKbps ?? 0,
      copyVideo: false,
    );
  }

  if (id == 'auto') {
    final rung = bestAutoRung(ladder, deviceMaxHeight);
    if (rung == null) {
      return (resolution: '1080p', bitrateKbps: 6000, copyVideo: false);
    }
    return (resolution: rung.resolution, bitrateKbps: rung.bitrateKbps, copyVideo: false);
  }

  for (final option in options) {
    if (option.id == qualityId && option.resolution.isNotEmpty && option.bitrateKbps > 0) {
      return (resolution: option.resolution, bitrateKbps: option.bitrateKbps, copyVideo: false);
    }
  }
  for (final rung in ladder) {
    if (rung.id == qualityId) {
      return (resolution: rung.resolution, bitrateKbps: rung.bitrateKbps, copyVideo: false);
    }
  }
  return null;
}
