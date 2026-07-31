import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/src/player/trickplay.dart';

TrickplayInfo sampleTrickplay({
  double intervalSeconds = 10,
  int width = 320,
  int height = 180,
  int tileColumns = 10,
  int tileRows = 10,
  int thumbnailCount = 150,
  List<TrickplaySheet>? sheets,
}) {
  return TrickplayInfo(
    intervalSeconds: intervalSeconds,
    width: width,
    height: height,
    tileColumns: tileColumns,
    tileRows: tileRows,
    thumbnailCount: thumbnailCount,
    sheets: sheets ??
        const [
          TrickplaySheet(index: 0, url: 'https://cdn.example/sheet-0.webp'),
          TrickplaySheet(index: 1, url: 'https://cdn.example/sheet-1.webp'),
        ],
  );
}

void main() {
  group('resolveTrickplayTile', () {
    test('returns null when trickplay is missing or empty', () {
      expect(resolveTrickplayTile(null, 12), isNull);
      expect(resolveTrickplayTile(sampleTrickplay(thumbnailCount: 0), 12), isNull);
      expect(resolveTrickplayTile(sampleTrickplay(sheets: const []), 12), isNull);
    });

    test('maps time onto the correct sheet crop with percentage sprites', () {
      // 125s → tile 12 → sheet 0, col 2, row 1
      final early = resolveTrickplayTile(sampleTrickplay(), 125);
      expect(early, isNotNull);
      expect(early!.url, 'https://cdn.example/sheet-0.webp');
      expect(early.width, 320);
      expect(early.height, 180);
      expect(early.col, 2);
      expect(early.row, 1);
      expect(early.columns, 10);
      expect(early.rows, 10);
      expect(early.backgroundPositionX, closeTo((2 / 9) * 100, 1e-9));
      expect(early.backgroundPositionY, closeTo((1 / 9) * 100, 1e-9));
      expect(early.alignmentX, closeTo((2 / 9) * 2 - 1, 1e-9));
      expect(early.alignmentY, closeTo((1 / 9) * 2 - 1, 1e-9));

      // 1050s → tile 105 → sheet 1, col 5, row 0
      final later = resolveTrickplayTile(sampleTrickplay(), 1050);
      expect(later!.url, 'https://cdn.example/sheet-1.webp');
      expect(later.col, 5);
      expect(later.row, 0);
      expect(later.backgroundPositionX, closeTo((5 / 9) * 100, 1e-9));
      expect(later.backgroundPositionY, 0);
    });

    test('clamps past the last thumbnail', () {
      final tile = resolveTrickplayTile(sampleTrickplay(), 99999);
      expect(tile?.url, 'https://cdn.example/sheet-1.webp');
      // last tile index 149 → local 49 → col 9, row 4
      expect(tile?.col, 9);
      expect(tile?.row, 4);
      expect(tile?.backgroundPositionX, 100);
      expect(tile?.backgroundPositionY, closeTo((4 / 9) * 100, 1e-9));
    });

    test('parses trickplay from watch JSON', () {
      final info = TrickplayInfo.fromJson({
        'interval_seconds': 10,
        'width': 320,
        'height': 180,
        'tile_columns': 10,
        'tile_rows': 10,
        'thumbnail_count': 12,
        'sheets': [
          {'index': 0, 'url': '/trickplay/0.webp'},
        ],
      });
      final tile = resolveTrickplayTile(info, 25);
      expect(tile?.url, '/trickplay/0.webp');
      expect(tile?.col, 2);
      expect(tile?.row, 0);
    });
  });
}
