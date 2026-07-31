/// Artwork URL helpers mirroring prairie-server `web/src/lib/artworkUrl.ts`.
///
/// Width variants live in the object key (`/original.`, `/w300.`, `/w500.`, …),
/// not query params. Path rewriting is skipped for third-party signed URLs
/// (SigV4 and friends) and for Prairie-signed `original` objects — rewriting
/// those invalidates the signature. Prairie's own width-rung signatures cover
/// the artwork *revision*, so selecting another `wN` rung still validates.
library;

/// Poster card design width (~140 CSS-px); w200 covers 1x and typical TV chrome scale.
const posterArtworkWidth = 200;

/// Landscape / continue-watching cards (~280 CSS-px); backdrops have no w500.
const landscapeArtworkWidth = 300;

/// Full-bleed hero / detail backdrop. Cap decode work at 1280.
const heroArtworkWidth = 1280;

/// Detail-page portrait poster (~160 CSS-px).
const detailPosterArtworkWidth = 300;

bool _hasQueryParam(String objectPath, String name) {
  final lower = objectPath.toLowerCase();
  final needle = '${name.toLowerCase()}=';
  return lower.contains('?$needle') || lower.contains('&$needle');
}

String _pathnameOf(String objectPath) {
  if (!objectPath.contains('://')) {
    final q = objectPath.indexOf('?');
    return q < 0 ? objectPath : objectPath.substring(0, q);
  }
  try {
    return Uri.parse(objectPath).path;
  } catch (_) {
    return '';
  }
}

/// True for a URL signed by this server's artwork store (`sig` + `expires` on `/artwork/`).
bool isPrairieSignedArtworkURL(String objectPath) {
  if (!_hasQueryParam(objectPath, 'sig') || !_hasQueryParam(objectPath, 'expires')) {
    return false;
  }
  return _pathnameOf(objectPath).contains('/artwork/');
}

/// True when rewriting the path would invalidate a third-party signature.
///
/// Prairie's own artwork signature is excluded — it covers the revision, not
/// the exact key — so width-rung rewrites remain valid.
bool isSignedArtworkURL(String objectPath) {
  if (isPrairieSignedArtworkURL(objectPath)) return false;
  // AWS SigV4, GCS, generic Signature, and Cloudflare WAF token (?verify=).
  final re = RegExp(r'[?&](X-Amz-Signature|X-Goog-Signature|Signature|sig|verify)=', caseSensitive: false);
  return re.hasMatch(objectPath);
}

/// True when the URL is a Prairie-signed `original` object (must not be rewritten).
bool isSignedOriginalArtworkURL(String objectPath) {
  if (!isPrairieSignedArtworkURL(objectPath)) return false;
  return RegExp(r'/original(?=\.)').hasMatch(_pathnameOf(objectPath));
}

String _rewritePathWidthVariant(String pathname, int width) {
  return pathname.replaceFirstMapped(
    RegExp(r'/(original|w\d+)(?=\.)'),
    (_) => '/w$width',
  );
}

/// Rewrites an artwork URL's width variant segment to `w{width}`.
///
/// Returns `null` when the URL cannot safely be rewritten (third-party signed,
/// signed original, or unrecognized path shape).
String? artworkWidthVariant(String? objectPath, int width) {
  final trimmed = objectPath?.trim() ?? '';
  if (trimmed.isEmpty || width <= 0) return null;
  if (isSignedArtworkURL(trimmed) || isSignedOriginalArtworkURL(trimmed)) return null;

  if (trimmed.contains('://')) {
    try {
      final u = Uri.parse(trimmed);
      final next = _rewritePathWidthVariant(u.path, width);
      if (next == u.path) return null;
      return u.replace(path: next).toString();
    } catch (_) {
      return null;
    }
  }

  final next = _rewritePathWidthVariant(trimmed, width);
  return next == trimmed ? null : next;
}

/// Prefer a width-variant rewrite when possible; otherwise keep the canonical URL.
String artworkSized(String? objectPath, int width) {
  final trimmed = objectPath?.trim() ?? '';
  if (trimmed.isEmpty) return '';
  if (width <= 0) return trimmed;
  return artworkWidthVariant(trimmed, width) ?? trimmed;
}
