import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:system_theme/system_theme.dart';

/// Builds [FluentThemeData] for PILAR ERP.
///
/// When [empresaColor] is provided it is converted to a full [AccentColor]
/// swatch. Otherwise the OS-level accent color (Windows/macOS) is used via
/// [SystemTheme.accentColor].
class PilarTheme {
  const PilarTheme._();

  static FluentThemeData build({
    required Brightness brightness,
    Color? empresaColor,
  }) {
    final accent = empresaColor != null
        ? empresaColor.toAccentColor()
        : SystemTheme.accentColor.accent.toAccentColor();

    return FluentThemeData(
      brightness: brightness,
      accentColor: accent,
      visualDensity: VisualDensity.standard,
      focusTheme: const FocusThemeData(glowFactor: 0.0),
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Controls the app-level theme mode (light / dark / system).
final themeBrightnessProvider =
    StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Accent color configured per empresa. Null means use the OS accent color.
final empresaColorProvider = StateProvider<Color?>((ref) => null);

/// Light [FluentThemeData] used by [FluentApp].
final pilarThemeProvider = Provider<FluentThemeData>((ref) {
  final empresaColor = ref.watch(empresaColorProvider);
  return PilarTheme.build(
    brightness: Brightness.light,
    empresaColor: empresaColor,
  );
});

/// Dark [FluentThemeData] used by [FluentApp].
final pilarDarkThemeProvider = Provider<FluentThemeData>((ref) {
  final empresaColor = ref.watch(empresaColorProvider);
  return PilarTheme.build(
    brightness: Brightness.dark,
    empresaColor: empresaColor,
  );
});
