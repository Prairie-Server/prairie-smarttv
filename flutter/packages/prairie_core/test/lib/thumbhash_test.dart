import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/src/lib/thumbhash.dart';

/// A portrait hash with no alpha whose AC scales are zero, so every decoded
/// pixel is the DC (average) color.
Uint8List _flatHash({int l = 40, int p = 20, int q = 50, int lx = 5}) {
  final header24 = l | (p << 6) | (q << 12);
  final header16 = lx;
  return Uint8List.fromList([
    header24 & 255,
    (header24 >> 8) & 255,
    (header24 >> 16) & 255,
    header16 & 255,
    (header16 >> 8) & 255,
    ...List.filled(24, 0),
  ]);
}

void main() {
  test('reads base64 with or without padding and rejects junk', () {
    final hash = _flatHash();
    final encoded = base64.encode(hash);
    expect(thumbHashBytes(encoded), hash);
    expect(thumbHashBytes(encoded.replaceAll('=', '')), hash);
    expect(thumbHashBytes(null), isNull);
    expect(thumbHashBytes('  '), isNull);
    expect(thumbHashBytes('not base64!'), isNull);
    expect(thumbHashBytes('AAAA'), isNull);
  });

  test('a portrait hash decodes 32 pixels tall at its aspect ratio', () {
    final hash = _flatHash(lx: 5);
    expect(thumbHashAspectRatio(hash), closeTo(5 / 7, 1e-9));
    final pixels = decodeThumbHash(hash);
    expect(pixels.height, 32);
    expect(pixels.width, 23);
    expect(pixels.rgba.length, 23 * 32 * 4);
  });

  test('with no detail every pixel is the average color', () {
    final hash = _flatHash();
    final average = thumbHashAverageColor(hash);
    final pixels = decodeThumbHash(hash);
    int byte(double channel) => (channel * 255).round();
    for (var i = 0; i < pixels.rgba.length; i += 4) {
      expect(pixels.rgba[i], byte(average.r));
      expect(pixels.rgba[i + 1], byte(average.g));
      expect(pixels.rgba[i + 2], byte(average.b));
      expect(pixels.rgba[i + 3], 255);
    }
  });

  test('full luminance with neutral chroma is white', () {
    // p and q of 31.5 are neutral; 31 and 32 straddle it, so allow a step.
    final color = thumbHashAverageColor(_flatHash(l: 63, p: 32, q: 32));
    expect(color.r, closeTo(1, 0.02));
    expect(color.g, closeTo(1, 0.02));
    expect(color.b, closeTo(1, 0.02));
  });
}
