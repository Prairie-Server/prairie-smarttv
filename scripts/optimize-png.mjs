#!/usr/bin/env node
/**
 * Losslessly re-encode the PNG assets that ship inside a TV package.
 *
 * Store rules pin these files to PNG (Tizen `<icon src>` and webOS
 * `appinfo.json` both reject anything else), so the only lever is encoding
 * quality. Exported PNGs are usually filtered and deflated badly: this script
 * re-filters every row with the standard minimum-sum heuristic, re-deflates at
 * maximum effort, and drops to an indexed palette when the image has 256 colours
 * or fewer — which logos and app marks almost always do.
 *
 * Every output is decoded again and compared pixel-for-pixel with the input
 * before it is written; a mismatch aborts without touching the file.
 *
 * Usage: node scripts/optimize-png.mjs [--check] [files…]
 *   --check  report savings without rewriting (used by CI / dry runs)
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { constants, deflateSync, inflateSync, crc32 } from "node:zlib";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");

const DEFAULT_TARGETS = [
  "platforms/tizen/icon.png",
  "platforms/tizen-legacy/icon.png",
  "platforms/webos/icon.png",
  "platforms/webos/largeIcon.png",
  "public/prairie-mark.png",
];

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function readChunks(buffer) {
  if (!buffer.subarray(0, 8).equals(PNG_SIGNATURE)) throw new Error("not a PNG");
  const chunks = [];
  let offset = 8;
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    chunks.push({ type, data });
    offset += 12 + length;
    if (type === "IEND") break;
  }
  return chunks;
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/** Decode 8-bit truecolour / truecolour+alpha / indexed PNG to RGBA. */
function decodePng(buffer) {
  const chunks = readChunks(buffer);
  const ihdr = chunks.find((chunk) => chunk.type === "IHDR");
  if (!ihdr) throw new Error("missing IHDR");
  const width = ihdr.data.readUInt32BE(0);
  const height = ihdr.data.readUInt32BE(4);
  const depth = ihdr.data[8];
  const colorType = ihdr.data[9];
  const interlace = ihdr.data[12];
  if (depth !== 8) throw new Error(`unsupported bit depth ${depth}`);
  if (interlace !== 0) throw new Error("interlaced PNGs are not supported");
  if (![2, 3, 6].includes(colorType)) throw new Error(`unsupported colour type ${colorType}`);

  const palette = chunks.find((chunk) => chunk.type === "PLTE")?.data ?? null;
  const transparency = chunks.find((chunk) => chunk.type === "tRNS")?.data ?? null;
  const channels = colorType === 6 ? 4 : colorType === 2 ? 3 : 1;
  const raw = inflateSync(
    Buffer.concat(chunks.filter((chunk) => chunk.type === "IDAT").map((chunk) => chunk.data)),
  );

  const stride = width * channels;
  const pixels = Buffer.alloc(height * stride);
  let previous = Buffer.alloc(stride);
  let position = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[position++];
    const line = Buffer.from(raw.subarray(position, position + stride));
    position += stride;
    for (let x = 0; x < stride; x++) {
      const left = x >= channels ? line[x - channels] : 0;
      const up = previous[x];
      const upLeft = x >= channels ? previous[x - channels] : 0;
      let value = line[x];
      if (filter === 1) value += left;
      else if (filter === 2) value += up;
      else if (filter === 3) value += (left + up) >> 1;
      else if (filter === 4) value += paeth(left, up, upLeft);
      else if (filter !== 0) throw new Error(`unknown row filter ${filter}`);
      line[x] = value & 0xff;
    }
    line.copy(pixels, y * stride);
    previous = line;
  }

  const rgba = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    if (colorType === 6) {
      pixels.copy(rgba, i * 4, i * 4, i * 4 + 4);
    } else if (colorType === 2) {
      rgba[i * 4] = pixels[i * 3];
      rgba[i * 4 + 1] = pixels[i * 3 + 1];
      rgba[i * 4 + 2] = pixels[i * 3 + 2];
      rgba[i * 4 + 3] = 255;
    } else {
      if (!palette) throw new Error("indexed PNG without PLTE");
      const index = pixels[i];
      rgba[i * 4] = palette[index * 3];
      rgba[i * 4 + 1] = palette[index * 3 + 1];
      rgba[i * 4 + 2] = palette[index * 3 + 2];
      rgba[i * 4 + 3] = transparency && index < transparency.length ? transparency[index] : 255;
    }
  }
  return { width, height, rgba };
}

function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, "ascii");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

/**
 * Filter each row with all five PNG filters and keep the one with the smallest
 * sum of absolute (signed) values — the heuristic every PNG encoder uses,
 * because it correlates well with how much deflate can then squeeze out.
 */
function filterRows(pixels, width, height, channels, forcedFilter = null) {
  const stride = width * channels;
  const out = Buffer.alloc(height * (stride + 1));
  const candidate = Buffer.alloc(stride);
  let previous = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const row = pixels.subarray(y * stride, (y + 1) * stride);
    let bestFilter = 0;
    let bestScore = Infinity;
    let best = null;
    const first = forcedFilter ?? 0;
    const last = forcedFilter ?? 4;
    for (let filter = first; filter <= last; filter++) {
      let score = 0;
      for (let x = 0; x < stride; x++) {
        const left = x >= channels ? row[x - channels] : 0;
        const up = previous[x];
        const upLeft = x >= channels ? previous[x - channels] : 0;
        let value = row[x];
        if (filter === 1) value -= left;
        else if (filter === 2) value -= up;
        else if (filter === 3) value -= (left + up) >> 1;
        else if (filter === 4) value -= paeth(left, up, upLeft);
        value &= 0xff;
        candidate[x] = value;
        score += value < 128 ? value : 256 - value;
      }
      if (score < bestScore) {
        bestScore = score;
        bestFilter = filter;
        best = Buffer.from(candidate);
      }
    }
    out[y * (stride + 1)] = bestFilter;
    best.copy(out, y * (stride + 1) + 1);
    previous = row;
  }
  return out;
}

/**
 * Deflate the filtered stream with every strategy zlib offers and keep the
 * smallest. Filtered image data often compresses better under Z_FILTERED or
 * Z_RLE than under the default strategy, and the cost is only a few extra
 * passes over an image we compress once, offline.
 */
function bestDeflate(filtered) {
  let best = null;
  for (const strategy of [
    constants.Z_DEFAULT_STRATEGY,
    constants.Z_FILTERED,
    constants.Z_RLE,
    constants.Z_HUFFMAN_ONLY,
  ]) {
    const candidate = deflateSync(filtered, { level: 9, memLevel: 9, strategy });
    if (!best || candidate.length < best.length) best = candidate;
  }
  return best;
}

function buildPng(ihdrData, filtered, extraChunks = []) {
  return Buffer.concat([
    PNG_SIGNATURE,
    chunk("IHDR", ihdrData),
    ...extraChunks,
    chunk("IDAT", bestDeflate(filtered)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/** Per-row minimum-sum heuristic, plus one pass with each filter forced. */
function filterStrategies(pixels, width, height, channels) {
  const variants = [filterRows(pixels, width, height, channels)];
  for (let filter = 0; filter <= 4; filter++) {
    variants.push(filterRows(pixels, width, height, channels, filter));
  }
  return variants;
}

function ihdr(width, height, colorType) {
  const data = Buffer.alloc(13);
  data.writeUInt32BE(width, 0);
  data.writeUInt32BE(height, 4);
  data[8] = 8;
  data[9] = colorType;
  return data;
}

/** Indexed encoding, or null when the image needs more than 256 colours. */
function encodeIndexed(width, height, rgba) {
  const lookup = new Map();
  const order = [];
  const indices = Buffer.alloc(width * height);
  for (let i = 0; i < width * height; i++) {
    const key =
      (rgba[i * 4] << 24) | (rgba[i * 4 + 1] << 16) | (rgba[i * 4 + 2] << 8) | rgba[i * 4 + 3];
    let index = lookup.get(key);
    if (index === undefined) {
      if (order.length >= 256) return null;
      index = order.length;
      lookup.set(key, index);
      order.push(i);
    }
    indices[i] = index;
  }
  const plte = Buffer.alloc(order.length * 3);
  const trns = Buffer.alloc(order.length);
  let needsAlpha = false;
  order.forEach((pixel, index) => {
    plte[index * 3] = rgba[pixel * 4];
    plte[index * 3 + 1] = rgba[pixel * 4 + 1];
    plte[index * 3 + 2] = rgba[pixel * 4 + 2];
    trns[index] = rgba[pixel * 4 + 3];
    if (trns[index] !== 255) needsAlpha = true;
  });
  const extras = [chunk("PLTE", plte)];
  if (needsAlpha) extras.push(chunk("tRNS", trns));
  return filterStrategies(indices, width, height, 1).map((filtered) =>
    buildPng(ihdr(width, height, 3), filtered, extras),
  );
}

function encodeTruecolor(width, height, rgba) {
  let opaque = true;
  for (let i = 3; i < rgba.length; i += 4) {
    if (rgba[i] !== 255) {
      opaque = false;
      break;
    }
  }
  if (opaque) {
    const rgb = Buffer.alloc(width * height * 3);
    for (let i = 0; i < width * height; i++) {
      rgb[i * 3] = rgba[i * 4];
      rgb[i * 3 + 1] = rgba[i * 4 + 1];
      rgb[i * 3 + 2] = rgba[i * 4 + 2];
    }
    return filterStrategies(rgb, width, height, 3).map((filtered) =>
      buildPng(ihdr(width, height, 2), filtered),
    );
  }
  return filterStrategies(rgba, width, height, 4).map((filtered) =>
    buildPng(ihdr(width, height, 6), filtered),
  );
}

function optimize(buffer) {
  const source = decodePng(buffer);
  const candidates = [...encodeTruecolor(source.width, source.height, source.rgba)];
  const indexed = encodeIndexed(source.width, source.height, source.rgba);
  if (indexed) candidates.push(...indexed);

  let best = buffer;
  for (const candidate of candidates) {
    if (candidate.length >= best.length) continue;
    // Never ship bytes we have not proven identical to the original image.
    const check = decodePng(candidate);
    if (check.width !== source.width || check.height !== source.height) continue;
    if (!check.rgba.equals(source.rgba)) continue;
    best = candidate;
  }
  return { best, width: source.width, height: source.height };
}

function main(args) {
  const checkOnly = args.includes("--check");
  const targets = args.filter((arg) => !arg.startsWith("--"));
  const files = targets.length > 0 ? targets : DEFAULT_TARGETS;

  let savedTotal = 0;
  let failed = false;
  for (const file of files) {
    const path = join(root, file);
    const original = readFileSync(path);
    let result;
    try {
      result = optimize(original);
    } catch (err) {
      console.error(`${relative(root, path)}: skipped (${err.message})`);
      failed = true;
      continue;
    }
    const saved = original.length - result.best.length;
    savedTotal += Math.max(0, saved);
    const percent = ((saved / original.length) * 100).toFixed(1);
    if (saved <= 0) {
      console.log(`${file}: already optimal (${original.length} B)`);
      continue;
    }
    console.log(
      `${file}: ${original.length} B → ${result.best.length} B (−${saved} B, −${percent}%)` +
        (checkOnly ? " [check only]" : ""),
    );
    if (!checkOnly) writeFileSync(path, result.best);
  }

  console.log(`${checkOnly ? "Could save" : "Saved"} ${(savedTotal / 1024).toFixed(1)} kB total`);
  if (failed) process.exitCode = 1;
}

export { decodePng, optimize };

// Importing this file (tests, tooling) must never rewrite assets as a side effect.
if (import.meta.main) {
  main(process.argv.slice(2));
}
