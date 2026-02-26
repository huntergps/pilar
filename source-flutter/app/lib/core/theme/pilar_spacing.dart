import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/config_service.dart';

// ---------------------------------------------------------------------------
// Base spacing constants — 4px grid
// ---------------------------------------------------------------------------

/// Base spacing scale using a 4px grid (unscaled constants).
///
/// Use [Spacing.all], [Spacing.symmetric], [Spacing.vertical], etc. for
/// const-compatible access without Riverpod.
///
/// For user-density-scaled values use [themedSpacingProvider] in ConsumerWidgets.
abstract final class Spacing {
  /// 0px
  static const double none = 0;

  /// 2px — minimal (internal padding for interactive elements)
  static const double xxs = 2;

  /// 4px — extra-small
  static const double xs = 4;

  /// 8px — small
  static const double sm = 8;

  /// 12px — medium-small
  static const double ms = 12;

  /// 16px — medium (base)
  static const double md = 16;

  /// 20px — medium-large
  static const double ml = 20;

  /// 24px — large
  static const double lg = 24;

  /// 32px — extra-large
  static const double xl = 32;

  /// 48px — 2x extra-large
  static const double xxl = 48;

  /// 64px — maximum
  static const double xxxl = 64;

  // -------------------------------------------------------------------------
  // Static helpers (factor = 1.0, const-compatible)
  // -------------------------------------------------------------------------

  static const EdgeInsetsAll       all       = EdgeInsetsAll._(1.0);
  static const EdgeInsetsSymmetric symmetric = EdgeInsetsSymmetric._(1.0);
  static const EdgeInsetsOnly      only      = EdgeInsetsOnly._();
  static const SizedBoxVertical    vertical  = SizedBoxVertical._(1.0);
  static const SizedBoxHorizontal  horizontal = SizedBoxHorizontal._(1.0);
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Current density factor, sourced from [ConfigService].
///
/// Default 1.0 (standard density). Range [0.50, 2.0].
/// Persists across sessions via [SharedPreferences].
final spacingFactorProvider = Provider<double>((ref) {
  return ref.watch(appConfigProvider).spacingFactor;
});

/// Scaled spacing instance driven by [spacingFactorProvider].
///
/// Usage:
/// ```dart
/// final s = ref.watch(themedSpacingProvider);
/// SizedBox(height: s.md)
/// Padding(padding: s.all.md)
/// s.vertical.sm  // SizedBox(height: 8 * factor)
/// ```
final themedSpacingProvider = Provider<ThemedSpacing>((ref) {
  return ThemedSpacing(ref.watch(spacingFactorProvider));
});

// ---------------------------------------------------------------------------
// ThemedSpacing — scaled values
// ---------------------------------------------------------------------------

/// Spacing helper that scales all values by the user's density [factor].
class ThemedSpacing {
  const ThemedSpacing(this.factor);

  final double factor;

  double get none  => Spacing.none;
  double get xxs   => Spacing.xxs  * factor;
  double get xs    => Spacing.xs   * factor;
  double get sm    => Spacing.sm   * factor;
  double get ms    => Spacing.ms   * factor;
  double get md    => Spacing.md   * factor;
  double get ml    => Spacing.ml   * factor;
  double get lg    => Spacing.lg   * factor;
  double get xl    => Spacing.xl   * factor;
  double get xxl   => Spacing.xxl  * factor;
  double get xxxl  => Spacing.xxxl * factor;

  EdgeInsetsAll       get all        => EdgeInsetsAll._(factor);
  EdgeInsetsSymmetric get symmetric  => EdgeInsetsSymmetric._(factor);
  EdgeInsetsOnly      get only       => const EdgeInsetsOnly._();
  SizedBoxVertical    get vertical   => SizedBoxVertical._(factor);
  SizedBoxHorizontal  get horizontal => SizedBoxHorizontal._(factor);
}

// ---------------------------------------------------------------------------
// EdgeInsets helpers
// ---------------------------------------------------------------------------

/// [EdgeInsets.all] shortcuts, optionally scaled by [factor].
class EdgeInsetsAll {
  final double _factor;
  const EdgeInsetsAll._(this._factor);

  EdgeInsets get none => EdgeInsets.zero;
  EdgeInsets get xxs  => EdgeInsets.all(Spacing.xxs * _factor);
  EdgeInsets get xs   => EdgeInsets.all(Spacing.xs  * _factor);
  EdgeInsets get sm   => EdgeInsets.all(Spacing.sm  * _factor);
  EdgeInsets get ms   => EdgeInsets.all(Spacing.ms  * _factor);
  EdgeInsets get md   => EdgeInsets.all(Spacing.md  * _factor);
  EdgeInsets get ml   => EdgeInsets.all(Spacing.ml  * _factor);
  EdgeInsets get lg   => EdgeInsets.all(Spacing.lg  * _factor);
  EdgeInsets get xl   => EdgeInsets.all(Spacing.xl  * _factor);
  EdgeInsets get xxl  => EdgeInsets.all(Spacing.xxl * _factor);
}

/// [EdgeInsets.symmetric] shortcuts, optionally scaled by [factor].
class EdgeInsetsSymmetric {
  final double _factor;
  const EdgeInsetsSymmetric._(this._factor);

  // Horizontal only
  EdgeInsets hNone() => EdgeInsets.zero;
  EdgeInsets hXs()   => EdgeInsets.symmetric(horizontal: Spacing.xs  * _factor);
  EdgeInsets hSm()   => EdgeInsets.symmetric(horizontal: Spacing.sm  * _factor);
  EdgeInsets hMs()   => EdgeInsets.symmetric(horizontal: Spacing.ms  * _factor);
  EdgeInsets hMd()   => EdgeInsets.symmetric(horizontal: Spacing.md  * _factor);
  EdgeInsets hMl()   => EdgeInsets.symmetric(horizontal: Spacing.ml  * _factor);
  EdgeInsets hLg()   => EdgeInsets.symmetric(horizontal: Spacing.lg  * _factor);
  EdgeInsets hXl()   => EdgeInsets.symmetric(horizontal: Spacing.xl  * _factor);

  // Vertical only
  EdgeInsets vNone() => EdgeInsets.zero;
  EdgeInsets vXs()   => EdgeInsets.symmetric(vertical: Spacing.xs  * _factor);
  EdgeInsets vSm()   => EdgeInsets.symmetric(vertical: Spacing.sm  * _factor);
  EdgeInsets vMs()   => EdgeInsets.symmetric(vertical: Spacing.ms  * _factor);
  EdgeInsets vMd()   => EdgeInsets.symmetric(vertical: Spacing.md  * _factor);
  EdgeInsets vMl()   => EdgeInsets.symmetric(vertical: Spacing.ml  * _factor);
  EdgeInsets vLg()   => EdgeInsets.symmetric(vertical: Spacing.lg  * _factor);
  EdgeInsets vXl()   => EdgeInsets.symmetric(vertical: Spacing.xl  * _factor);

  // Both axes
  EdgeInsets both({double h = Spacing.md, double v = Spacing.md}) =>
      EdgeInsets.symmetric(horizontal: h * _factor, vertical: v * _factor);
}

/// [EdgeInsets.only] shortcuts (raw values, not scaled).
class EdgeInsetsOnly {
  const EdgeInsetsOnly._();

  EdgeInsets left(double v)   => EdgeInsets.only(left: v);
  EdgeInsets right(double v)  => EdgeInsets.only(right: v);
  EdgeInsets top(double v)    => EdgeInsets.only(top: v);
  EdgeInsets bottom(double v) => EdgeInsets.only(bottom: v);
}

// ---------------------------------------------------------------------------
// SizedBox helpers
// ---------------------------------------------------------------------------

/// [SizedBox] with height, optionally scaled by [factor].
class SizedBoxVertical {
  final double _factor;
  const SizedBoxVertical._(this._factor);

  SizedBox get none => const SizedBox.shrink();
  SizedBox get xxs  => SizedBox(height: Spacing.xxs * _factor);
  SizedBox get xs   => SizedBox(height: Spacing.xs  * _factor);
  SizedBox get sm   => SizedBox(height: Spacing.sm  * _factor);
  SizedBox get ms   => SizedBox(height: Spacing.ms  * _factor);
  SizedBox get md   => SizedBox(height: Spacing.md  * _factor);
  SizedBox get ml   => SizedBox(height: Spacing.ml  * _factor);
  SizedBox get lg   => SizedBox(height: Spacing.lg  * _factor);
  SizedBox get xl   => SizedBox(height: Spacing.xl  * _factor);
  SizedBox get xxl  => SizedBox(height: Spacing.xxl * _factor);
}

/// [SizedBox] with width, optionally scaled by [factor].
class SizedBoxHorizontal {
  final double _factor;
  const SizedBoxHorizontal._(this._factor);

  SizedBox get none => const SizedBox.shrink();
  SizedBox get xxs  => SizedBox(width: Spacing.xxs * _factor);
  SizedBox get xs   => SizedBox(width: Spacing.xs  * _factor);
  SizedBox get sm   => SizedBox(width: Spacing.sm  * _factor);
  SizedBox get ms   => SizedBox(width: Spacing.ms  * _factor);
  SizedBox get md   => SizedBox(width: Spacing.md  * _factor);
  SizedBox get ml   => SizedBox(width: Spacing.ml  * _factor);
  SizedBox get lg   => SizedBox(width: Spacing.lg  * _factor);
  SizedBox get xl   => SizedBox(width: Spacing.xl  * _factor);
  SizedBox get xxl  => SizedBox(width: Spacing.xxl * _factor);
}

// ---------------------------------------------------------------------------
// num extensions — quick gap widgets
// ---------------------------------------------------------------------------

/// Quick gap widgets from a raw pixel value.
///
/// ```dart
/// 16.verticalSpace    // SizedBox(height: 16)
/// 8.horizontalSpace   // SizedBox(width: 8)
/// 24.squareSpace      // SizedBox.square(dimension: 24)
/// ```
extension SpacingWidgetExtension on num {
  SizedBox get verticalSpace   => SizedBox(height: toDouble());
  SizedBox get horizontalSpace => SizedBox(width: toDouble());
  SizedBox get squareSpace     => SizedBox.square(dimension: toDouble());
}

/// Scale a raw pixel value by a factor.
extension ScaledSpacingExtension on num {
  double scaled(double factor) => toDouble() * factor;
}
