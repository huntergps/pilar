import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:system_theme/system_theme.dart';

import '../config/app_config_model.dart';
import '../services/config_service.dart';

/// Builds [FluentThemeData] for PILAR ERP.
///
/// Accent color priority (highest → lowest):
///   1. [config.accentColor] — user's local override (set in Configuración)
///   2. [empresaColor]        — empresa's [color_primario] from Supabase
///   3. OS accent color       — [SystemTheme.accentColor]
///
/// Each typography level is scaled independently by its own factor from
/// [AppConfigModel], so the user can fine-tune e.g. only Caption size.
class PilarTheme {
  const PilarTheme._();

  static FluentThemeData build({
    required Brightness brightness,
    required AppConfigModel config,
    Color? empresaColor,
  }) {
    // --- Accent color resolution ---
    final AccentColor accent;
    if (config.accentColor != null) {
      accent = config.accentColor!;
    } else if (empresaColor != null) {
      accent = empresaColor.toAccentColor();
    } else {
      accent = SystemTheme.accentColor.accent.toAccentColor();
    }

    // --- Per-level typography scaling ---
    final baseTypo = Typography.fromBrightness(brightness: brightness);
    final typography = _isAllDefault(config)
        ? baseTypo
        : _scaleTypography(baseTypo, config);

    return FluentThemeData(
      brightness: brightness,
      accentColor: accent,
      typography: typography,
      visualDensity: VisualDensity.standard,
      focusTheme: const FocusThemeData(glowFactor: 0.0),
    );
  }

  /// Returns true when all 7 factors are effectively 1.0 (no scaling needed).
  static bool _isAllDefault(AppConfigModel c) =>
      (c.displayFactor    - 1.0).abs() < 0.001 &&
      (c.titleLargeFactor - 1.0).abs() < 0.001 &&
      (c.titleFactor      - 1.0).abs() < 0.001 &&
      (c.bodyLargeFactor  - 1.0).abs() < 0.001 &&
      (c.bodyStrongFactor - 1.0).abs() < 0.001 &&
      (c.bodyFactor       - 1.0).abs() < 0.001 &&
      (c.captionFactor    - 1.0).abs() < 0.001;

  static Typography _scaleTypography(Typography base, AppConfigModel c) {
    return base.merge(Typography.raw(
      display:    _scale(base.display,    c.displayFactor),
      titleLarge: _scale(base.titleLarge, c.titleLargeFactor),
      title:      _scale(base.title,      c.titleFactor),
      subtitle:   base.subtitle, // not exposed — keeps the original
      bodyLarge:  _scale(base.bodyLarge,  c.bodyLargeFactor),
      bodyStrong: _scale(base.bodyStrong, c.bodyStrongFactor),
      body:       _scale(base.body,       c.bodyFactor),
      caption:    _scale(base.caption,    c.captionFactor),
    ));
  }

  static TextStyle? _scale(TextStyle? style, double factor) {
    if (style == null || style.fontSize == null) return style;
    return style.copyWith(fontSize: style.fontSize! * factor);
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Accent color sourced from the active empresa's [color_primario] field.
/// Null = no empresa color configured → falls back to OS accent color.
///
/// Updated by the empresa onboarding/branding flow.
final empresaColorProvider = StateProvider<Color?>((ref) => null);

/// Controls the app-level theme mode (light / dark / system).
/// Derived from [appConfigProvider] — persists automatically.
final themeBrightnessProvider = Provider<ThemeMode>((ref) {
  return ref.watch(appConfigProvider).themeMode;
});

