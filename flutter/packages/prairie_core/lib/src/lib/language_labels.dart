/// ISO 639 language code → English display name. Covers the common ISO 639-1
/// (2-letter) and ISO 639-2/B (3-letter) tags that container metadata / the
/// Prairie API put on audio and subtitle tracks.
const _languageDisplayNames = <String, String>{
  // ISO 639-1
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
  'nl': 'Dutch',
  'pl': 'Polish',
  'ru': 'Russian',
  'sv': 'Swedish',
  'no': 'Norwegian',
  'nb': 'Norwegian',
  'nn': 'Norwegian',
  'da': 'Danish',
  'fi': 'Finnish',
  'ar': 'Arabic',
  'hi': 'Hindi',
  'cs': 'Czech',
  'el': 'Greek',
  'he': 'Hebrew',
  'hu': 'Hungarian',
  'ro': 'Romanian',
  'tr': 'Turkish',
  'th': 'Thai',
  'vi': 'Vietnamese',
  'uk': 'Ukrainian',
  // ISO 639-2/B
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

/// Titles that are accessibility/disposition tags rather than a human track
/// name — e.g. a PGS track titled "SDH" should become an "SDH" tag on the
/// language label, not replace the language entirely.
const _accessibilityTitleTags = <String>{
  'sdh',
  'hi',
  'cc',
  'forced',
  'forced narrative',
  'signs',
  'songs',
};

/// Returns true when [raw] looks like a codec/format identifier rather than
/// a human language or track title (e.g. `HDMV_PGS_SUBTITLE`, `S_HDMV/PGS`).
bool looksLikeCodecLabel(String raw) {
  if (raw.contains('/')) return true;
  final lower = raw.toLowerCase();
  if (raw.contains('_') && _codecLikeMarkers.any(lower.contains)) return true;
  return _codecLikeMarkers.any(lower.contains) && !raw.contains(' ');
}

/// True when [raw] is solely an accessibility/disposition tag (SDH, HI, …).
bool isAccessibilityTitleTag(String raw) {
  return _accessibilityTitleTags.contains(raw.trim().toLowerCase());
}

/// Strips a BCP-47 region/script suffix (`en-US` → `en`) for language lookup.
String _languageLookupKey(String raw) {
  final lower = raw.trim().toLowerCase();
  final dash = lower.indexOf('-');
  if (dash > 0) return lower.substring(0, dash);
  final underscore = lower.indexOf('_');
  if (underscore > 0) return lower.substring(0, underscore);
  return lower;
}

/// Humanizes a subtitle/audio track's raw language string for display —
/// e.g. a bare code like "eng" / "en" becomes "English", and free text like
/// "english (sdh)" becomes "English (Sdh)" rather than showing the source's
/// original casing verbatim.
String humanizeTrackLanguage(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'Unknown';
  final known = _languageDisplayNames[_languageLookupKey(trimmed)];
  if (known != null) return known;
  if (looksLikeCodecLabel(trimmed)) return 'Unknown';
  // Bare 2–3 letter codes we don't recognize still shouldn't display raw.
  if (RegExp(r'^[a-zA-Z]{2,3}$').hasMatch(trimmed)) return 'Unknown';
  return trimmed
      .split(RegExp(r'(\s+)'))
      .map((word) => word.trim().isEmpty ? word : word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join();
}

/// Returns a display-worthy string from [raw], or null when empty / codec-like.
String? usefulTrackLabel(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (looksLikeCodecLabel(trimmed)) return null;
  return trimmed;
}
