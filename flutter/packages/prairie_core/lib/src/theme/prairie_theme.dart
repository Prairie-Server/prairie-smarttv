import 'package:flutter/material.dart';

/// Prairie's dark, warm-amber TV theme — ported from src/styles.css's
/// `:root` custom properties. Bundles the same two typefaces the TS app
/// used via `@fontsource` (Sora for UI, Fraunces for display/headings).
///
/// There is currently no server-supplied theming API (checked src/api/** —
/// nothing exposes branding/theme config), so this is a static port of the
/// TS app's CSS palette, not yet inheriting anything from the server. If
/// server-driven theming becomes a real requirement, it needs a Prairie API
/// endpoint to exist first.
class PrairieColors {
  static const bg = Color(0xFF141820);
  static const bgElevated = Color(0xFF1C2430);
  static const bgSoft = Color(0xFF222B38);
  static const amber = Color(0xFFE0A84A);
  static const amberDeep = Color(0xFFC48C2E);
  static const amberBright = Color(0xFFF0C574);
  static const ink = Color(0xFFF3EFE6);
  static const muted = Color(0xFF9AA3B2);
  static const danger = Color(0xFFE07070);
  static const ring = Color(0xFFF0C574);

  /// Focus fill for solid TV focus chrome (Settings rows/sidebar, the
  /// profile/settings menu) — noticeably darker than [amberDeep] (a fairly
  /// bright orange used elsewhere as a border/accent, not meant to fill a
  /// large area behind text) and used without the amber glow shadow, which
  /// stacked with the fill to read as "obnoxiously bright."
  static const focusFill = Color(0xFF6C4D19);
}

/// Ported 1:1 from `body`'s layered background in src/styles.css: a dark
/// diagonal linear gradient with two soft radial highlights (amber
/// top-left, blue top-right). CSS radial-gradients are positioned in
/// viewport percent + pixel radius; Flutter's [RadialGradient] takes an
/// [Alignment] + relative radius instead, so the positions/sizes below are
/// the closest equivalent rather than an exact formula translation.
class PrairieBackground extends StatelessWidget {
  const PrairieBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.7, -1),
              end: Alignment(0.7, 1),
              colors: [Color(0xFF10151C), PrairieColors.bg, Color(0xFF0F1319)],
              stops: [0.0, 0.42, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.76, -1.2),
              radius: 0.9,
              colors: [PrairieColors.amber.withValues(alpha: 0.16), PrairieColors.amber.withValues(alpha: 0)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.76, -0.84),
              radius: 0.75,
              colors: [const Color(0xFF466EA0).withValues(alpha: 0.22), const Color(0xFF466EA0).withValues(alpha: 0)],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Solid focus ring that follows border-radius (Tizen paints CSS `outline` as
/// a square). Mirrors `--focus-ring-solid`.
List<BoxShadow> prairieFocusRing({double width = 3}) => [
  BoxShadow(color: PrairieColors.ring, blurRadius: 0, spreadRadius: width),
];

ButtonStyle _prairiePrimaryButtonStyle() {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return PrairieColors.amber.withValues(alpha: 0.35);
      }
      // Brighter amber when focused — filled primary alone is hard to read as
      // "focused" next to outline siblings.
      if (states.contains(WidgetState.focused)) return PrairieColors.amberBright;
      return PrairieColors.amber;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return PrairieColors.bg.withValues(alpha: 0.55);
      }
      return PrairieColors.bg;
    }),
    // High-contrast cream ring on amber fill (not another amber outline).
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return const BorderSide(color: PrairieColors.ink, width: 3);
      }
      return BorderSide.none;
    }),
    elevation: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) return 8;
      return 0;
    }),
    shadowColor: WidgetStateProperty.all(PrairieColors.ring.withValues(alpha: 0.55)),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
    textStyle: WidgetStateProperty.all(const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w600, fontSize: 16)),
    shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    overlayColor: WidgetStateProperty.all(PrairieColors.ink.withValues(alpha: 0.12)),
  );
}

ButtonStyle _prairieSecondaryButtonStyle() {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      // Invert on focus (TS `.focus-btn--secondary:focus`) — much clearer than
      // a faint amber border on a dark ghost button.
      if (states.contains(WidgetState.focused)) return PrairieColors.ink;
      return const Color(0x8C0A0C10);
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) return PrairieColors.bg;
      return PrairieColors.ink;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return const BorderSide(color: PrairieColors.ring, width: 3);
      }
      return BorderSide(color: PrairieColors.ink.withValues(alpha: 0.24));
    }),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
    textStyle: WidgetStateProperty.all(const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w600, fontSize: 16)),
    shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    overlayColor: WidgetStateProperty.all(PrairieColors.amber.withValues(alpha: 0.12)),
  );
}

ButtonStyle _prairieGhostButtonStyle() {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) return PrairieColors.ink;
      return Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) return PrairieColors.bg;
      return PrairieColors.muted;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return const BorderSide(color: PrairieColors.ring, width: 3);
      }
      return BorderSide.none;
    }),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
    textStyle: WidgetStateProperty.all(const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w600)),
    shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
  );
}

ThemeData buildPrairieTheme() {
  const colorScheme = ColorScheme.dark(
    surface: PrairieColors.bg,
    primary: PrairieColors.amber,
    secondary: PrairieColors.amberDeep,
    onSecondary: Colors.white,
    secondaryContainer: PrairieColors.amber,
    onSecondaryContainer: Colors.white,
    onSurface: PrairieColors.ink,
    error: PrairieColors.danger,
  );

  final base = ThemeData(colorScheme: colorScheme, fontFamily: 'Sora', useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: PrairieColors.ink,
      elevation: 0,
    ),
    cardColor: PrairieColors.bgElevated,
    textTheme: base.textTheme
        .apply(bodyColor: PrairieColors.ink, displayColor: PrairieColors.ink)
        .copyWith(
          headlineLarge: const TextStyle(fontFamily: 'Fraunces', color: PrairieColors.ink),
          headlineMedium: const TextStyle(fontFamily: 'Fraunces', color: PrairieColors.ink),
          headlineSmall: const TextStyle(fontFamily: 'Fraunces', color: PrairieColors.ink),
          titleLarge: const TextStyle(fontFamily: 'Fraunces', color: PrairieColors.ink),
        ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: _prairiePrimaryButtonStyle()),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _prairieSecondaryButtonStyle()),
    textButtonTheme: TextButtonThemeData(style: _prairieGhostButtonStyle()),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return PrairieColors.bg;
          return PrairieColors.amber;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return PrairieColors.ink;
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return const BorderSide(color: PrairieColors.ring, width: 3);
          }
          return BorderSide.none;
        }),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      // Solid amber so selected chips carry white label text clearly on TV.
      selectedColor: PrairieColors.amber,
      backgroundColor: PrairieColors.bgElevated.withValues(alpha: 0.72),
      checkmarkColor: Colors.white,
      // Unselected
      labelStyle: const TextStyle(color: PrairieColors.ink, fontWeight: FontWeight.w500),
      // Selected — Material ChoiceChip uses secondaryLabelStyle for the
      // selected label; previously this was PrairieColors.bg (near-black),
      // which made library/collection sort chips unreadable.
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      side: BorderSide(color: PrairieColors.ink.withValues(alpha: 0.16)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PrairieColors.bgSoft,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PrairieColors.ring, width: 3),
      ),
    ),
    listTileTheme: const ListTileThemeData(textColor: PrairieColors.ink, iconColor: PrairieColors.muted),
    // Prefer the darker settings focus fill for Material overlays too —
    // bright ring-as-fill washes out text on solid controls.
    focusColor: PrairieColors.focusFill.withValues(alpha: 0.85),
    highlightColor: PrairieColors.focusFill.withValues(alpha: 0.35),
    hoverColor: PrairieColors.focusFill.withValues(alpha: 0.2),
  );
}
