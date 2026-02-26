import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

/// Immutable snapshot of the user's local app preferences.
///
/// Persisted via [SharedPreferences] and managed by [ConfigService].
/// These are *user-device* preferences — not empresa settings stored in DB.
class AppConfigModel {
  const AppConfigModel({
    required this.themeMode,
    this.accentColor,
    required this.displayFactor,
    required this.titleLargeFactor,
    required this.titleFactor,
    required this.bodyLargeFactor,
    required this.bodyStrongFactor,
    required this.bodyFactor,
    required this.captionFactor,
    required this.spacingFactor,
    required this.paneDisplayMode,
    required this.windowEffect,
  });

  /// Selected brightness. [ThemeMode.system] follows the OS setting.
  final ThemeMode themeMode;

  /// User's local accent color override.
  /// Null = derive from empresa [color_primario] or OS accent color.
  final AccentColor? accentColor;

  // ---------------------------------------------------------------------------
  // Typography per-level scale factors (range 0.50 – 2.00, default 1.0)
  // Each factor scales only that text style's fontSize.
  // ---------------------------------------------------------------------------

  /// Display text (largest): section headers, hero labels.
  final double displayFactor;

  /// Title Large: page headers, panel titles.
  final double titleLargeFactor;

  /// Title: card headers, dialog titles.
  final double titleFactor;

  /// Body Large: lead paragraph, prominent body copy.
  final double bodyLargeFactor;

  /// Body Strong: labels, form field names, emphasized body.
  final double bodyStrongFactor;

  /// Body: standard paragraph text, list items.
  final double bodyFactor;

  /// Caption / Subtitle: hints, metadata, secondary labels.
  final double captionFactor;

  // ---------------------------------------------------------------------------
  // Layout & window
  // ---------------------------------------------------------------------------

  /// Spacing density factor applied via [ThemedSpacing]. Range 0.50 – 2.0. Default 1.0.
  final double spacingFactor;

  /// Navigation pane display mode.
  /// [PaneDisplayMode.auto] (default) lets fluent_ui decide based on window width.
  /// Users can override to [open], [compact], or [minimal].
  final PaneDisplayMode paneDisplayMode;

  /// Desktop window translucency effect.
  /// Windows: acrylic / mica / disabled
  /// macOS:   sidebar / disabled
  /// Other:   ignored
  final WindowEffect windowEffect;

  // ---------------------------------------------------------------------------
  // Defaults
  // ---------------------------------------------------------------------------

  static const AppConfigModel defaults = AppConfigModel(
    themeMode: ThemeMode.system,
    accentColor: null,
    displayFactor: 1.0,
    titleLargeFactor: 1.0,
    titleFactor: 1.0,
    bodyLargeFactor: 1.0,
    bodyStrongFactor: 1.0,
    bodyFactor: 1.0,
    captionFactor: 1.0,
    spacingFactor: 1.0,
    paneDisplayMode: PaneDisplayMode.auto,
    windowEffect: WindowEffect.acrylic,
  );

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  AppConfigModel copyWith({
    ThemeMode? themeMode,
    Object? accentColor = _sentinel, // sentinel to allow clearing to null
    double? displayFactor,
    double? titleLargeFactor,
    double? titleFactor,
    double? bodyLargeFactor,
    double? bodyStrongFactor,
    double? bodyFactor,
    double? captionFactor,
    double? spacingFactor,
    PaneDisplayMode? paneDisplayMode,
    WindowEffect? windowEffect,
  }) {
    return AppConfigModel(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor == _sentinel
          ? this.accentColor
          : accentColor as AccentColor?,
      displayFactor: displayFactor ?? this.displayFactor,
      titleLargeFactor: titleLargeFactor ?? this.titleLargeFactor,
      titleFactor: titleFactor ?? this.titleFactor,
      bodyLargeFactor: bodyLargeFactor ?? this.bodyLargeFactor,
      bodyStrongFactor: bodyStrongFactor ?? this.bodyStrongFactor,
      bodyFactor: bodyFactor ?? this.bodyFactor,
      captionFactor: captionFactor ?? this.captionFactor,
      spacingFactor: spacingFactor ?? this.spacingFactor,
      paneDisplayMode: paneDisplayMode ?? this.paneDisplayMode,
      windowEffect: windowEffect ?? this.windowEffect,
    );
  }

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfigModel &&
          other.themeMode == themeMode &&
          other.accentColor == accentColor &&
          other.displayFactor == displayFactor &&
          other.titleLargeFactor == titleLargeFactor &&
          other.titleFactor == titleFactor &&
          other.bodyLargeFactor == bodyLargeFactor &&
          other.bodyStrongFactor == bodyStrongFactor &&
          other.bodyFactor == bodyFactor &&
          other.captionFactor == captionFactor &&
          other.spacingFactor == spacingFactor &&
          other.paneDisplayMode == paneDisplayMode &&
          other.windowEffect == windowEffect;

  @override
  int get hashCode => Object.hash(
        themeMode,
        accentColor,
        displayFactor,
        titleLargeFactor,
        titleFactor,
        bodyLargeFactor,
        bodyStrongFactor,
        bodyFactor,
        captionFactor,
        spacingFactor,
        paneDisplayMode,
        windowEffect,
      );
}

// Sentinel object to distinguish "not passed" from "explicitly null" in copyWith.
const _sentinel = Object();
