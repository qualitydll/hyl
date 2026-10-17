import 'package:flutter/material.dart';

import '../brand.dart';

/// Material You scheme; the default crew orange gets a coffee-brown tertiary.
ColorScheme crewScheme(Color seed, Brightness b, DynamicSchemeVariant v) {
  final s = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: b,
    dynamicSchemeVariant: v,
  );
  if (seed.toARGB32() != kCrewOrange.toARGB32()) return s;
  final c = ColorScheme.fromSeed(
    seedColor: kCrewCoffee,
    brightness: b,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  return s.copyWith(
    tertiary: c.primary,
    onTertiary: c.onPrimary,
    tertiaryContainer: c.primaryContainer,
    onTertiaryContainer: c.onPrimaryContainer,
  );
}

ThemeData buildTheme(ColorScheme scheme) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final t = base.textTheme.apply(
    fontFamily: kBrandFont,
    fontFamilyFallback: kBrandFallback,
  );
  TextStyle? head(TextStyle? s) =>
      s?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: t.copyWith(
      displayLarge: head(t.displayLarge),
      displayMedium: head(t.displayMedium),
      displaySmall: head(t.displaySmall),
      headlineLarge: head(t.headlineLarge),
      headlineMedium: head(t.headlineMedium),
      headlineSmall: head(t.headlineSmall),
      titleLarge: t.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      labelType: NavigationRailLabelType.all,
      selectedLabelTextStyle: TextStyle(
        fontFamily: kBrandFont,
        fontFamilyFallback: kBrandFallback,
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: kBrandFont,
        fontFamilyFallback: kBrandFallback,
        color: scheme.onSurfaceVariant,
        fontSize: 12,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

const seedPalette = <Color>[
  kCrewOrange,
  kCrewCoffee,
  kCrewCaramel,
  Color(0xFFB3261E),
  Color(0xFF984061),
  Color(0xFF6750A4),
  Color(0xFF0061A4),
  Color(0xFF006A6A),
  Color(0xFF386A20),
];

const variantNames = {
  DynamicSchemeVariant.tonalSpot: 'Спокойная',
  DynamicSchemeVariant.expressive: 'Выразительная',
  DynamicSchemeVariant.vibrant: 'Яркая',
  DynamicSchemeVariant.fidelity: 'Точная',
  DynamicSchemeVariant.rainbow: 'Радуга',
  DynamicSchemeVariant.fruitSalad: 'Фруктовая',
  DynamicSchemeVariant.content: 'Контент',
  DynamicSchemeVariant.monochrome: 'Монохром',
  DynamicSchemeVariant.neutral: 'Нейтральная',
};
