/// ISO 639-2/B → English display name, for humanizing whatever raw language
/// tag a track carries (often a bare 3-letter code, sometimes a lowercase
/// word straight from container metadata).
const _languageDisplayNames = <String, String>{
  'eng': 'English',
  'spa': 'Spanish',
  'fra': 'French',
  'fre': 'French',
  'deu': 'German',
  'ger': 'German',
  'ita': 'Italian',
  'por': 'Portuguese',
  'jpn': 'Japanese',
  'kor': 'Korean',
  'chi': 'Chinese',
  'zho': 'Chinese',
  'nld': 'Dutch',
  'dut': 'Dutch',
  'pol': 'Polish',
  'rus': 'Russian',
  'swe': 'Swedish',
  'nor': 'Norwegian',
  'dan': 'Danish',
  'fin': 'Finnish',
  'ara': 'Arabic',
  'hin': 'Hindi',
  'und': 'Unknown',
};

/// Substrings that mark a "language" value as actually a codec/format
/// identifier — some sources (container metadata, or the server itself for
/// image-based tracks like PGS) put the codec where the language belongs
/// when no real language tag exists, e.g. "hdmv_pgs_subtitle" or
/// "S_HDMV/PGS". Title-casing that verbatim reads as gibberish, not a label.
const _codecLikeMarkers = <String>['pgs', 'vobsub', 'dvbsub', 'hdmv', 'subtitle', 'subrip'];

bool _looksLikeCodecLabel(String raw) {
  if (raw.contains('/')) return true;
  final lower = raw.toLowerCase();
  if (raw.contains('_') && _codecLikeMarkers.any(lower.contains)) return true;
  return _codecLikeMarkers.any(lower.contains) && !raw.contains(' ');
}

/// Humanizes a subtitle/audio track's raw language string for display —
/// e.g. a bare code like "eng" becomes "English", and free text like
/// "english (sdh)" becomes "English (Sdh)" rather than showing the source's
/// original casing verbatim.
String humanizeTrackLanguage(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'Unknown';
  final known = _languageDisplayNames[trimmed.toLowerCase()];
  if (known != null) return known;
  if (_looksLikeCodecLabel(trimmed)) return 'Unknown';
  return trimmed
      .split(RegExp(r'(\s+)'))
      .map((word) => word.trim().isEmpty ? word : word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join();
}
