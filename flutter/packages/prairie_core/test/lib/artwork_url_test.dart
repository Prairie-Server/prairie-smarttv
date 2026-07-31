import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/src/lib/artwork_url.dart';

void main() {
  group('isPrairieSignedArtworkURL', () {
    test('requires sig + expires on /artwork/ path', () {
      final signed = '/artwork/tmdb/movies/550/poster/w500.rev.webp?expires=123&sig=abc';
      expect(isPrairieSignedArtworkURL(signed), isTrue);
      expect(isPrairieSignedArtworkURL('/artwork/x/w500.rev.webp?expires=1'), isFalse);
      expect(isPrairieSignedArtworkURL('https://cdn.example.com/art/w500.webp?sig=abc'), isFalse);
    });
  });

  group('isSignedArtworkURL', () {
    test('matches third-party signatures but not Prairie artwork sigs', () {
      expect(
        isSignedArtworkURL('https://cdn.example.com/art/w300.webp?X-Amz-Signature=abc'),
        isTrue,
      );
      expect(
        isSignedArtworkURL('https://cdn.example.com/art/w300.webp?verify=123-abc'),
        isTrue,
      );
      expect(
        isSignedArtworkURL('/artwork/tmdb/movies/550/poster/w500.rev.webp?expires=123&sig=abc'),
        isFalse,
      );
    });
  });

  group('isSignedOriginalArtworkURL', () {
    test('detects Prairie-signed original objects', () {
      final signed =
          '/artwork/tmdb/movies/550/poster/original.rev.webp?expires=123&sig=abc';
      expect(isSignedOriginalArtworkURL(signed), isTrue);
      expect(
        isSignedOriginalArtworkURL('/artwork/tmdb/movies/550/poster/w500.rev.webp?expires=123&sig=abc'),
        isFalse,
      );
    });
  });

  group('artworkWidthVariant', () {
    test('rewrites width rung in path', () {
      expect(artworkWidthVariant('/art/poster/w300.webp', 500), '/art/poster/w500.webp');
      expect(
        artworkWidthVariant('https://cdn.example.com/art/w300.rev.webp?v=1', 1920),
        'https://cdn.example.com/art/w1920.rev.webp?v=1',
      );
    });

    test('rewrites Prairie-signed width rungs', () {
      final signed = '/artwork/tmdb/movies/550/poster/w500.rev.webp?expires=123&sig=abc';
      expect(
        artworkWidthVariant(signed, 200),
        '/artwork/tmdb/movies/550/poster/w200.rev.webp?expires=123&sig=abc',
      );
    });

    test('bails on third-party signed and signed originals', () {
      expect(
        artworkWidthVariant('https://cdn.example.com/art/w300.webp?X-Amz-Signature=abc', 500),
        isNull,
      );
      expect(
        artworkWidthVariant(
          '/artwork/tmdb/movies/550/poster/original.rev.webp?expires=123&sig=abc',
          200,
        ),
        isNull,
      );
    });
  });

  group('artworkSized', () {
    test('falls back to original when rewrite is unsafe', () {
      const signed = 'https://cdn.example.com/art/w300.webp?X-Amz-Signature=abc';
      expect(artworkSized(signed, 200), signed);
    });

    test('returns rewritten URL when possible', () {
      expect(artworkSized('/art/poster/w500.webp', 200), '/art/poster/w200.webp');
    });
  });
}
