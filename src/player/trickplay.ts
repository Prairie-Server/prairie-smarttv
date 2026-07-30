export interface TrickplaySheet {
  index: number;
  url: string;
}

export interface TrickplayInfo {
  interval_seconds: number;
  width: number;
  height: number;
  tile_columns: number;
  tile_rows: number;
  thumbnail_count: number;
  sheets: TrickplaySheet[];
}

export interface TrickplayTilePreview {
  url: string;
  width: number;
  height: number;
  backgroundPosition: string;
  backgroundSize: string;
}

/** Resolve the sprite-sheet crop for a media time, matching the web SeekBar. */
export function resolveTrickplayTile(
  trickplay: TrickplayInfo | null | undefined,
  seconds: number,
): TrickplayTilePreview | null {
  if (!trickplay || trickplay.thumbnail_count <= 0 || !trickplay.sheets?.length) {
    return null;
  }
  const interval = trickplay.interval_seconds > 0 ? trickplay.interval_seconds : 10;
  const columns = trickplay.tile_columns > 0 ? trickplay.tile_columns : 10;
  const rows = trickplay.tile_rows > 0 ? trickplay.tile_rows : 10;
  const width = trickplay.width > 0 ? trickplay.width : 320;
  const height = trickplay.height > 0 ? trickplay.height : Math.round((width * 9) / 16);
  const tilesPerSheet = columns * rows;
  const tileIndex = Math.min(
    Math.max(0, Math.floor(seconds / interval)),
    Math.max(0, trickplay.thumbnail_count - 1),
  );
  const sheetIndex = Math.floor(tileIndex / tilesPerSheet);
  const sheet = trickplay.sheets.find((entry) => entry.index === sheetIndex);
  if (!sheet?.url) {
    return null;
  }
  const local = tileIndex % tilesPerSheet;
  const col = local % columns;
  const row = Math.floor(local / columns);
  return {
    url: sheet.url,
    width,
    height,
    backgroundPosition: `-${col * width}px -${row * height}px`,
    backgroundSize: `${columns * width}px ${rows * height}px`,
  };
}

/** Warm the browser image cache for sheets near the current position. */
export function prefetchTrickplaySheets(
  trickplay: TrickplayInfo | null | undefined,
  seconds: number,
  radius = 1,
): void {
  if (!trickplay?.sheets?.length || typeof Image === "undefined") {
    return;
  }
  const interval = trickplay.interval_seconds > 0 ? trickplay.interval_seconds : 10;
  const columns = trickplay.tile_columns > 0 ? trickplay.tile_columns : 10;
  const rows = trickplay.tile_rows > 0 ? trickplay.tile_rows : 10;
  const tilesPerSheet = columns * rows;
  const tileIndex = Math.min(
    Math.max(0, Math.floor(seconds / interval)),
    Math.max(0, trickplay.thumbnail_count - 1),
  );
  const center = Math.floor(tileIndex / tilesPerSheet);
  for (let offset = -radius; offset <= radius; offset += 1) {
    const sheet = trickplay.sheets.find((entry) => entry.index === center + offset);
    if (!sheet?.url) continue;
    const img = new Image();
    img.decoding = "async";
    img.src = sheet.url;
  }
}
