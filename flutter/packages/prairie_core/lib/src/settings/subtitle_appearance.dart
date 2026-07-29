/// Mirrors src/settings/subtitleAppearance.ts, including a Flutter-side
/// equivalent of `subtitleAppearanceCssVars` for PlayerScreen's overlay
/// (`subtitleAppearanceTextStyle`/`subtitleAppearanceBottomFraction` below).
library;

import 'package:flutter/painting.dart';

enum SubtitleFontSize { small, medium, large, xlarge, xxlarge }

enum SubtitleBackgroundStyle { box, shadow, outline, none }

enum SubtitlePosition { bottom, lowerThird, top }

String subtitleFontSizeWire(SubtitleFontSize v) => v.name;
String subtitleBackgroundStyleWire(SubtitleBackgroundStyle v) => v.name;
String subtitlePositionWire(SubtitlePosition v) => switch (v) {
  SubtitlePosition.lowerThird => 'lower-third',
  _ => v.name,
};

T _asEnum<T>(String? value, List<T> allowed, T fallback, String Function(T) wire) {
  if (value == null) return fallback;
  for (final option in allowed) {
    if (wire(option) == value) return option;
  }
  return fallback;
}

bool _isHexColor(String? value) => value != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value);

class SubtitleAppearance {
  const SubtitleAppearance({
    this.fontSize = SubtitleFontSize.large,
    this.fontColor = '#ffffff',
    this.backgroundColor = '#000000',
    this.backgroundStyle = SubtitleBackgroundStyle.none,
    this.backgroundOpacity = 75,
    this.textOutline = true,
    this.textOutlineColor = '#000000',
    this.position = SubtitlePosition.bottom,
  });

  final SubtitleFontSize fontSize;
  final String fontColor;
  final String backgroundColor;
  final SubtitleBackgroundStyle backgroundStyle;
  final int backgroundOpacity;
  final bool textOutline;
  final String textOutlineColor;
  final SubtitlePosition position;

  SubtitleAppearance copyWith({
    SubtitleFontSize? fontSize,
    String? fontColor,
    String? backgroundColor,
    SubtitleBackgroundStyle? backgroundStyle,
    int? backgroundOpacity,
    bool? textOutline,
    String? textOutlineColor,
    SubtitlePosition? position,
  }) => SubtitleAppearance(
    fontSize: fontSize ?? this.fontSize,
    fontColor: fontColor ?? this.fontColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    backgroundStyle: backgroundStyle ?? this.backgroundStyle,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    textOutline: textOutline ?? this.textOutline,
    textOutlineColor: textOutlineColor ?? this.textOutlineColor,
    position: position ?? this.position,
  );

  Map<String, dynamic> toJson() => {
    'fontSize': subtitleFontSizeWire(fontSize),
    'fontColor': fontColor,
    'backgroundColor': backgroundColor,
    'backgroundStyle': subtitleBackgroundStyleWire(backgroundStyle),
    'backgroundOpacity': backgroundOpacity,
    'textOutline': textOutline,
    'textOutlineColor': textOutlineColor,
    'position': subtitlePositionWire(position),
  };

  factory SubtitleAppearance.fromJson(Map<String, dynamic>? json) {
    const fallback = SubtitleAppearance();
    if (json == null) return fallback;
    final opacity = json['backgroundOpacity'];
    return SubtitleAppearance(
      fontSize: _asEnum(json['fontSize'] as String?, SubtitleFontSize.values, fallback.fontSize, subtitleFontSizeWire),
      fontColor: _isHexColor(json['fontColor'] as String?) ? json['fontColor'] as String : fallback.fontColor,
      backgroundColor: _isHexColor(json['backgroundColor'] as String?) ? json['backgroundColor'] as String : fallback.backgroundColor,
      backgroundStyle: _asEnum(json['backgroundStyle'] as String?, SubtitleBackgroundStyle.values, fallback.backgroundStyle, subtitleBackgroundStyleWire),
      backgroundOpacity: opacity is num ? opacity.round().clamp(0, 100) : fallback.backgroundOpacity,
      textOutline: json['textOutline'] == true,
      textOutlineColor: _isHexColor(json['textOutlineColor'] as String?) ? json['textOutlineColor'] as String : fallback.textOutlineColor,
      position: _asEnum(json['position'] as String?, SubtitlePosition.values, fallback.position, subtitlePositionWire),
    );
  }
}

/// Mirrors `SUBTITLE_COLOR_CHOICES`/`SUBTITLE_BG_COLOR_CHOICES`.
const subtitleColorChoices = [
  ('#ffffff', 'White'),
  ('#ffff00', 'Yellow'),
  ('#00ff00', 'Green'),
  ('#00ffff', 'Cyan'),
  ('#ff00ff', 'Magenta'),
  ('#e0a84a', 'Amber'),
];

const subtitleBgColorChoices = [
  ('#000000', 'Black'),
  ('#141820', 'Slate'),
  ('#1a1a1a', 'Charcoal'),
];

const _fontSizePx = {
  SubtitleFontSize.small: 20.0,
  SubtitleFontSize.medium: 24.0,
  SubtitleFontSize.large: 30.0,
  SubtitleFontSize.xlarge: 38.0,
  SubtitleFontSize.xxlarge: 46.0,
};

const _positionBottomFraction = {
  SubtitlePosition.top: 0.82,
  SubtitlePosition.lowerThird: 0.18,
  SubtitlePosition.bottom: 0.06,
};

Color _colorFromHex(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

/// Fraction of the player surface's height, measured from the bottom, that
/// the caption should sit at. Mirrors `POSITION_BOTTOM_PCT`.
double subtitleAppearanceBottomFraction(SubtitleAppearance appearance) => _positionBottomFraction[appearance.position]!;

/// Text style for the caption. Mirrors the text half of
/// `subtitleAppearanceCssVars` (outline via multi-directional shadows).
TextStyle subtitleAppearanceTextStyle(SubtitleAppearance appearance) {
  final outline = _colorFromHex(appearance.textOutlineColor);
  final wantsOutline = appearance.backgroundStyle == SubtitleBackgroundStyle.outline || appearance.textOutline;
  return TextStyle(
    color: _colorFromHex(appearance.fontColor),
    fontSize: _fontSizePx[appearance.fontSize],
    fontWeight: FontWeight.w600,
    shadows: wantsOutline
        ? [
            Shadow(color: outline, offset: const Offset(1, 0)),
            Shadow(color: outline, offset: const Offset(-1, 0)),
            Shadow(color: outline, offset: const Offset(0, 1)),
            Shadow(color: outline, offset: const Offset(0, -1)),
          ]
        : null,
  );
}

/// Background decoration behind the caption text, or `null` for none.
/// Mirrors the `backgroundStyle === "box"` branch of `subtitleAppearanceCssVars`.
Color? subtitleAppearanceBackgroundColor(SubtitleAppearance appearance) {
  if (appearance.backgroundStyle != SubtitleBackgroundStyle.box) return null;
  final opacity = appearance.backgroundOpacity / 100;
  if (opacity <= 0) return null;
  return _colorFromHex(appearance.backgroundColor).withValues(alpha: opacity);
}
