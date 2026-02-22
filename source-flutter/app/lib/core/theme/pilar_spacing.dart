import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Base spacing scale using a 4px grid.
abstract final class Spacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;
}

/// Spacing helper that scales all values by a density [factor].
///
/// Obtain via [themedSpacingProvider] in Riverpod widgets.
class ThemedSpacing {
  const ThemedSpacing(this.factor);

  final double factor;

  double get xxs => Spacing.xxs * factor;
  double get xs => Spacing.xs * factor;
  double get sm => Spacing.sm * factor;
  double get md => Spacing.md * factor;
  double get lg => Spacing.lg * factor;
  double get xl => Spacing.xl * factor;
  double get xxl => Spacing.xxl * factor;

  /// Returns [EdgeInsets.all] scaled by [factor].
  EdgeInsets all(double v) => EdgeInsets.all(v * factor);

  /// Returns [EdgeInsets.symmetric] scaled by [factor].
  EdgeInsets symmetric({double h = 0, double v = 0}) =>
      EdgeInsets.symmetric(horizontal: h * factor, vertical: v * factor);
}

/// Current density factor. Default 1.0 (standard density).
final spacingFactorProvider = StateProvider<double>((ref) => 1.0);

/// Scaled spacing instance driven by [spacingFactorProvider].
final themedSpacingProvider = Provider<ThemedSpacing>((ref) {
  final factor = ref.watch(spacingFactorProvider);
  return ThemedSpacing(factor);
});
