// Pick the encode ladder resolution for POST /playback/transcode/start.
// Mirrors `src/api/targetResolution.ts`.

const _resolutionHeight = <String, int>{
  '2160p': 2160,
  '4k': 2160,
  'uhd': 2160,
  '3840x2160': 2160,
  '1440p': 1440,
  '2560x1440': 1440,
  '1080p': 1080,
  '1920x1080': 1080,
  '720p': 720,
  '1280x720': 720,
  '480p': 480,
  '420p': 420,
  '360p': 360,
};

/// Canonical Prairie resolution token (`2160p`, `1080p`, …), or "" if unknown.
String normalizeResolution(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value.isEmpty) return '';
  final mapped = _resolutionHeight[value];
  if (mapped == 2160) return '2160p';
  if (mapped == 1440) return '1440p';
  if (mapped == 1080) return '1080p';
  if (mapped == 720) return '720p';
  if (mapped == 480) return '480p';
  if (mapped == 420) return '420p';
  if (mapped == 360) return '360p';
  final match = RegExp(r'(\d{3,4})\s*[pP]?$').firstMatch(value);
  if (match != null) {
    final height = int.tryParse(match.group(1)!) ?? 0;
    if (height >= 2160) return '2160p';
    if (height >= 1440) return '1440p';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height >= 480) return '480p';
    return '360p';
  }
  return '';
}

int _height(String token) => _resolutionHeight[token] ?? 0;

/// `min(source, device max)` as a Prairie resolution token.
String resolveTargetResolution(String? sourceResolution, String? maxResolution) {
  final max = normalizeResolution(maxResolution).isEmpty ? '1080p' : normalizeResolution(maxResolution);
  final source = normalizeResolution(sourceResolution);
  if (source.isEmpty) return max;
  return _height(source) <= _height(max) ? source : max;
}

/// Bitrate ladder matched to the chosen target resolution.
int targetBitrateKbpsForResolution(String resolution) {
  switch (normalizeResolution(resolution)) {
    case '2160p':
      return 20000;
    case '1440p':
      return 12000;
    case '1080p':
      return 6000;
    case '720p':
      return 3000;
    case '480p':
      return 1500;
    default:
      return 6000;
  }
}
