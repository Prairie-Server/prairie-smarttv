/// Interval sprite sheets for seek scrubbing previews (server FileVersion.trickplay).
class TrickplaySheet {
  const TrickplaySheet({required this.index, required this.url});

  final int index;
  final String url;

  factory TrickplaySheet.fromJson(Map<String, dynamic> json) => TrickplaySheet(
    index: json['index'] as int,
    url: json['url'] as String,
  );
}

/// Mirrors web `PlayerTrickplay` / `VersionTrickplay`.
class TrickplayInfo {
  const TrickplayInfo({
    required this.intervalSeconds,
    required this.width,
    required this.height,
    required this.tileColumns,
    required this.tileRows,
    required this.thumbnailCount,
    this.sheets = const [],
  });

  final double intervalSeconds;
  final int width;
  final int height;
  final int tileColumns;
  final int tileRows;
  final int thumbnailCount;
  final List<TrickplaySheet> sheets;

  factory TrickplayInfo.fromJson(Map<String, dynamic> json) => TrickplayInfo(
    intervalSeconds: (json['interval_seconds'] as num?)?.toDouble() ?? 0,
    width: (json['width'] as num?)?.toInt() ?? 0,
    height: (json['height'] as num?)?.toInt() ?? 0,
    tileColumns: (json['tile_columns'] as num?)?.toInt() ?? 0,
    tileRows: (json['tile_rows'] as num?)?.toInt() ?? 0,
    thumbnailCount: (json['thumbnail_count'] as num?)?.toInt() ?? 0,
    sheets: (json['sheets'] as List<dynamic>? ?? [])
        .map((j) => TrickplaySheet.fromJson(j as Map<String, dynamic>))
        .toList(),
  );
}

/// Resolved sprite crop for a media time — matches web SeekBar percentage math.
class TrickplayTilePreview {
  const TrickplayTilePreview({
    required this.url,
    required this.width,
    required this.height,
    required this.columns,
    required this.rows,
    required this.col,
    required this.row,
    required this.alignmentX,
    required this.alignmentY,
    required this.backgroundPositionX,
    required this.backgroundPositionY,
  });

  final String url;
  final int width;
  final int height;

  /// Sheet grid size (used as CSS `background-size: columns*100% rows*100%`).
  final int columns;
  final int rows;

  /// Zero-based tile coordinates within the sheet.
  final int col;
  final int row;

  /// Flutter [Alignment] x/y in −1…1, derived from CSS percentage position.
  final double alignmentX;
  final double alignmentY;

  /// CSS `background-position` percentages (0–100).
  final double backgroundPositionX;
  final double backgroundPositionY;
}

/// Resolve the sprite-sheet crop for a media time, matching web SeekBar.
TrickplayTilePreview? resolveTrickplayTile(TrickplayInfo? trickplay, double seconds) {
  if (trickplay == null || trickplay.thumbnailCount <= 0 || trickplay.sheets.isEmpty) {
    return null;
  }
  final interval = trickplay.intervalSeconds > 0 ? trickplay.intervalSeconds : 10.0;
  final columns = trickplay.tileColumns > 0 ? trickplay.tileColumns : 10;
  final rows = trickplay.tileRows > 0 ? trickplay.tileRows : 10;
  final width = trickplay.width > 0 ? trickplay.width : 320;
  final height = trickplay.height > 0 ? trickplay.height : ((width * 9) / 16).round();
  final tilesPerSheet = columns * rows;
  final tileIndex = (seconds / interval).floor().clamp(0, trickplay.thumbnailCount - 1);
  final sheetIndex = tileIndex ~/ tilesPerSheet;
  TrickplaySheet? sheet;
  for (final entry in trickplay.sheets) {
    if (entry.index == sheetIndex) {
      sheet = entry;
      break;
    }
  }
  if (sheet == null || sheet.url.isEmpty) return null;

  final local = tileIndex % tilesPerSheet;
  final col = local % columns;
  final row = local ~/ columns;
  // Percentage sprite math scales with the rendered preview size.
  final backgroundPositionX = columns > 1 ? (col / (columns - 1)) * 100 : 0.0;
  final backgroundPositionY = rows > 1 ? (row / (rows - 1)) * 100 : 0.0;
  final alignmentX = columns > 1 ? (col / (columns - 1)) * 2 - 1 : 0.0;
  final alignmentY = rows > 1 ? (row / (rows - 1)) * 2 - 1 : 0.0;

  return TrickplayTilePreview(
    url: sheet.url,
    width: width,
    height: height,
    columns: columns,
    rows: rows,
    col: col,
    row: row,
    alignmentX: alignmentX,
    alignmentY: alignmentY,
    backgroundPositionX: backgroundPositionX,
    backgroundPositionY: backgroundPositionY,
  );
}
