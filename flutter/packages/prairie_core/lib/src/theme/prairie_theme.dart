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
  static const ink = Color(0xFFF3EFE6);
  static const muted = Color(0xFF9AA3B2);
  static const danger = Color(0xFFE07070);
  static const ring = Color(0xFFF0C574);
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

ThemeData buildPrairieTheme() {
  const colorScheme = ColorScheme.dark(
    surface: PrairieColors.bg,
    primary: PrairieColors.amber,
    secondary: PrairieColors.amberDeep,
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
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: PrairieColors.amber,
        foregroundColor: PrairieColors.bg,
        textStyle: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
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
    focusColor: PrairieColors.ring,
  );
}
