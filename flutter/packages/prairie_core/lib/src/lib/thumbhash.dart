import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A ThumbHash decoded to pixels: [width] x [height] RGBA, row-major.
class ThumbHashPixels {
  const ThumbHashPixels({required this.width, required this.height, required this.rgba});

  final int width;
  final int height;
  final Uint8List rgba;
}

/// The bytes of a base64 ThumbHash as the server sends it (`*_thumbhash`),
/// or null when [value] is empty or not base64. Padding is optional.
Uint8List? thumbHashBytes(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  try {
    final bytes = base64.decode(base64.normalize(trimmed));
    // Five header bytes plus at least one AC byte.
    return bytes.length < 6 ? null : bytes;
  } on FormatException {
    return null;
  }
}

/// The hash's average color: what a card shows while the blur decodes.
Color thumbHashAverageColor(Uint8List hash) {
  final header = hash[0] | (hash[1] << 8) | (hash[2] << 16);
  final l = (header & 63) / 63;
  final p = ((header >> 6) & 63) / 31.5 - 1;
  final q = ((header >> 12) & 63) / 31.5 - 1;
  final hasAlpha = (header >> 23) != 0;
  final a = hasAlpha ? (hash[5] & 15) / 15 : 1.0;
  final b = l - 2 / 3 * p;
  final r = (3 * l - b + q) / 2;
  final g = r - q;
  int channel(double v) => (255 * v.clamp(0.0, 1.0)).round();
  return Color.fromARGB(channel(a), channel(r), channel(g), channel(b));
}

/// Width over height of the image the hash was made from, roughly.
double thumbHashAspectRatio(Uint8List hash) {
  final header = hash[3];
  final hasAlpha = (hash[2] & 0x80) != 0;
  final isLandscape = (hash[4] & 0x80) != 0;
  final lx = isLandscape ? (hasAlpha ? 5 : 7) : header & 7;
  final ly = isLandscape ? header & 7 : (hasAlpha ? 5 : 7);
  return ly == 0 ? 1 : lx / ly;
}

/// Decodes [hash] to at most 32 x 32 pixels, following the reference
/// ThumbHash decoder (evanw/thumbhash, `thumbHashToRGBA`).
ThumbHashPixels decodeThumbHash(Uint8List hash) {
  final header24 = hash[0] | (hash[1] << 8) | (hash[2] << 16);
  final header16 = hash[3] | (hash[4] << 8);
  final lDc = (header24 & 63) / 63;
  final pDc = ((header24 >> 6) & 63) / 31.5 - 1;
  final qDc = ((header24 >> 12) & 63) / 31.5 - 1;
  final lScale = ((header24 >> 18) & 31) / 31;
  final hasAlpha = (header24 >> 23) != 0;
  final pScale = ((header16 >> 3) & 63) / 63;
  final qScale = ((header16 >> 9) & 63) / 63;
  final isLandscape = (header16 >> 15) != 0;
  final lx = math.max(3, isLandscape ? (hasAlpha ? 5 : 7) : header16 & 7);
  final ly = math.max(3, isLandscape ? header16 & 7 : (hasAlpha ? 5 : 7));
  final aDc = hasAlpha ? (hash[5] & 15) / 15 : 1.0;
  final aScale = (hash[5] >> 4) / 15;

  // The varying factors, saturation boosted 1.25x for quantization.
  final acStart = hasAlpha ? 6 : 5;
  var acIndex = 0;
  List<double> decodeChannel(int nx, int ny, double scale) {
    final ac = <double>[];
    for (var cy = 0; cy < ny; cy++) {
      for (var cx = cy > 0 ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
        final byteIndex = acStart + (acIndex >> 1);
        final byte = byteIndex < hash.length ? hash[byteIndex] : 0;
        ac.add((((byte >> ((acIndex & 1) << 2)) & 15) / 7.5 - 1) * scale);
        acIndex++;
      }
    }
    return ac;
  }

  final lAc = decodeChannel(lx, ly, lScale);
  final pAc = decodeChannel(3, 3, pScale * 1.25);
  final qAc = decodeChannel(3, 3, qScale * 1.25);
  final aAc = hasAlpha ? decodeChannel(5, 5, aScale) : const <double>[];

  final ratio = thumbHashAspectRatio(hash);
  final w = (ratio > 1 ? 32 : 32 * ratio).round().clamp(1, 32);
  final h = (ratio > 1 ? 32 / ratio : 32).round().clamp(1, 32);
  final rgba = Uint8List(w * h * 4);
  final fx = List<double>.filled(math.max(lx, hasAlpha ? 5 : 3), 0);
  final fy = List<double>.filled(math.max(ly, hasAlpha ? 5 : 3), 0);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++, i += 4) {
      var l = lDc, p = pDc, q = qDc, a = aDc;
      for (var cx = 0; cx < fx.length; cx++) {
        fx[cx] = math.cos(math.pi / w * (x + 0.5) * cx);
      }
      for (var cy = 0; cy < fy.length; cy++) {
        fy[cy] = math.cos(math.pi / h * (y + 0.5) * cy);
      }
      for (var cy = 0, j = 0; cy < ly; cy++) {
        final fy2 = fy[cy] * 2;
        for (var cx = cy > 0 ? 0 : 1; cx * ly < lx * (ly - cy); cx++, j++) {
          l += lAc[j] * fx[cx] * fy2;
        }
      }
      for (var cy = 0, j = 0; cy < 3; cy++) {
        final fy2 = fy[cy] * 2;
        for (var cx = cy > 0 ? 0 : 1; cx < 3 - cy; cx++, j++) {
          final f = fx[cx] * fy2;
          p += pAc[j] * f;
          q += qAc[j] * f;
        }
      }
      if (hasAlpha) {
        for (var cy = 0, j = 0; cy < 5; cy++) {
          final fy2 = fy[cy] * 2;
          for (var cx = cy > 0 ? 0 : 1; cx < 5 - cy; cx++, j++) {
            a += aAc[j] * fx[cx] * fy2;
          }
        }
      }
      final b = l - 2 / 3 * p;
      final r = (3 * l - b + q) / 2;
      final g = r - q;
      rgba[i] = (255 * r.clamp(0.0, 1.0)).round();
      rgba[i + 1] = (255 * g.clamp(0.0, 1.0)).round();
      rgba[i + 2] = (255 * b.clamp(0.0, 1.0)).round();
      rgba[i + 3] = (255 * a.clamp(0.0, 1.0)).round();
    }
  }
  return ThumbHashPixels(width: w, height: h, rgba: rgba);
}

/// A blurred stand-in for artwork that is loading or missing, drawn from the
/// server's ThumbHash: the average color at once, then the decoded blur.
/// Draws nothing but [fallback] when [hash] is absent or malformed.
class ThumbHashImage extends StatefulWidget {
  const ThumbHashImage({super.key, required this.hash, this.fit = BoxFit.cover, this.fallback});

  /// The base64 hash (`poster_thumbhash`, `still_thumbhash`, ...).
  final String? hash;
  final BoxFit fit;
  final Widget? fallback;

  @override
  State<ThumbHashImage> createState() => _ThumbHashImageState();
}

class _ThumbHashImageState extends State<ThumbHashImage> {
  Uint8List? _bytes;
  ui.Image? _image;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(ThumbHashImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hash != widget.hash) _decode();
  }

  void _decode() {
    final generation = ++_generation;
    _image?.dispose();
    _image = null;
    final bytes = thumbHashBytes(widget.hash);
    _bytes = bytes;
    if (bytes == null) return;
    final ThumbHashPixels pixels;
    try {
      pixels = decodeThumbHash(bytes);
    } catch (_) {
      // A hash the decoder can't read keeps the average color.
      return;
    }
    ui.decodeImageFromPixels(pixels.rgba, pixels.width, pixels.height, ui.PixelFormat.rgba8888, (image) {
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    });
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.fallback ?? const SizedBox.expand();
    final image = _image;
    if (image == null) return ColoredBox(color: thumbHashAverageColor(bytes), child: const SizedBox.expand());
    return RawImage(image: image, fit: widget.fit, filterQuality: FilterQuality.low);
  }
}
