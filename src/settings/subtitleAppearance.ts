/** Subtitle look-and-feel mirrored from Prairie mobile/TV clients. */

export type SubtitleFontSize = "small" | "medium" | "large" | "xlarge" | "xxlarge";
export type SubtitleBackgroundStyle = "box" | "shadow" | "outline" | "none";
export type SubtitlePosition = "bottom" | "lower-third" | "top";

export interface SubtitleAppearance {
  fontSize: SubtitleFontSize;
  fontColor: string;
  backgroundColor: string;
  backgroundStyle: SubtitleBackgroundStyle;
  backgroundOpacity: number;
  textOutline: boolean;
  textOutlineColor: string;
  position: SubtitlePosition;
}

export const DEFAULT_SUBTITLE_APPEARANCE: SubtitleAppearance = {
  fontSize: "large",
  fontColor: "#ffffff",
  backgroundColor: "#000000",
  backgroundStyle: "none",
  backgroundOpacity: 75,
  textOutline: true,
  textOutlineColor: "#000000",
  position: "bottom",
};

const FONT_SIZES: SubtitleFontSize[] = ["small", "medium", "large", "xlarge", "xxlarge"];
const BG_STYLES: SubtitleBackgroundStyle[] = ["box", "shadow", "outline", "none"];
const POSITIONS: SubtitlePosition[] = ["bottom", "lower-third", "top"];

const FONT_SIZE_PX: Record<SubtitleFontSize, number> = {
  small: 28,
  medium: 36,
  large: 48,
  xlarge: 60,
  xxlarge: 72,
};

const POSITION_BOTTOM_PCT: Record<SubtitlePosition, number> = {
  top: 82,
  "lower-third": 18,
  bottom: 6,
};

function isHexColor(value: string): boolean {
  return /^#[0-9a-fA-F]{6}$/.test(value);
}

function asEnum<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return typeof value === "string" && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : fallback;
}

export function normalizeSubtitleAppearance(
  input: Partial<SubtitleAppearance> | null | undefined,
): SubtitleAppearance {
  const merged = { ...DEFAULT_SUBTITLE_APPEARANCE, ...input };
  const opacity =
    typeof merged.backgroundOpacity === "number" && Number.isFinite(merged.backgroundOpacity)
      ? Math.min(100, Math.max(0, Math.round(merged.backgroundOpacity)))
      : DEFAULT_SUBTITLE_APPEARANCE.backgroundOpacity;

  return {
    fontSize: asEnum(merged.fontSize, FONT_SIZES, DEFAULT_SUBTITLE_APPEARANCE.fontSize),
    fontColor: isHexColor(merged.fontColor)
      ? merged.fontColor
      : DEFAULT_SUBTITLE_APPEARANCE.fontColor,
    backgroundColor: isHexColor(merged.backgroundColor)
      ? merged.backgroundColor
      : DEFAULT_SUBTITLE_APPEARANCE.backgroundColor,
    backgroundStyle: asEnum(
      merged.backgroundStyle,
      BG_STYLES,
      DEFAULT_SUBTITLE_APPEARANCE.backgroundStyle,
    ),
    backgroundOpacity: opacity,
    textOutline: merged.textOutline === true,
    textOutlineColor: isHexColor(merged.textOutlineColor)
      ? merged.textOutlineColor
      : DEFAULT_SUBTITLE_APPEARANCE.textOutlineColor,
    position: asEnum(merged.position, POSITIONS, DEFAULT_SUBTITLE_APPEARANCE.position),
  };
}

/** CSS custom properties applied to the player host for ::cue styling. */
export function subtitleAppearanceCssVars(appearance: SubtitleAppearance): Record<string, string> {
  const normalized = normalizeSubtitleAppearance(appearance);
  const opacity = normalized.backgroundOpacity / 100;
  const bg = hexToRgba(normalized.backgroundColor, opacity);
  const fontPx = FONT_SIZE_PX[normalized.fontSize];
  const bottom = POSITION_BOTTOM_PCT[normalized.position];

  let textShadow = "none";
  // Explicit "Outline" background style wins over the textOutline toggle so the
  // picker is not shadowed by the default outline-on setting.
  if (normalized.backgroundStyle === "outline") {
    const outline = normalized.textOutlineColor;
    textShadow = [
      `1px 0 0 ${outline}`,
      `-1px 0 0 ${outline}`,
      `0 1px 0 ${outline}`,
      `0 -1px 0 ${outline}`,
    ].join(", ");
  } else if (normalized.backgroundStyle === "shadow" || normalized.textOutline) {
    const outline = normalized.textOutlineColor;
    textShadow = [
      `0 0 2px ${outline}`,
      `0 0 4px ${outline}`,
      `1px 1px 0 ${outline}`,
      `-1px -1px 0 ${outline}`,
    ].join(", ");
  }

  const background = normalized.backgroundStyle === "box" && opacity > 0 ? bg : "transparent";

  return {
    "--prairie-sub-color": normalized.fontColor,
    "--prairie-sub-bg": background,
    "--prairie-sub-size": `${fontPx}px`,
    "--prairie-sub-shadow": textShadow,
    "--prairie-sub-bottom": `${bottom}%`,
  };
}

export function hexToRgba(hex: string, alpha: number): string {
  const raw = hex.startsWith("#") ? hex.slice(1) : hex;
  const r = Number.parseInt(raw.slice(0, 2), 16);
  const g = Number.parseInt(raw.slice(2, 4), 16);
  const b = Number.parseInt(raw.slice(4, 6), 16);
  const a = Math.min(1, Math.max(0, alpha));
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}

export const SUBTITLE_COLOR_CHOICES = [
  { hex: "#ffffff", label: "White" },
  { hex: "#ffff00", label: "Yellow" },
  { hex: "#00ff00", label: "Green" },
  { hex: "#00ffff", label: "Cyan" },
  { hex: "#ff00ff", label: "Magenta" },
  { hex: "#e0a84a", label: "Amber" },
] as const;

export const SUBTITLE_BG_COLOR_CHOICES = [
  { hex: "#000000", label: "Black" },
  { hex: "#141820", label: "Slate" },
  { hex: "#1a1a1a", label: "Charcoal" },
] as const;
