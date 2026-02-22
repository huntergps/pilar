import 'package:flutter/widgets.dart';

/// Layout breakpoints and default window dimensions for PilarShell.
abstract final class PilarBreakpoints {
  /// Below this width: mobile layout (drawer nav, bottom nav).
  static const double mobile = 600;

  /// Between [mobile] and [tablet]: tablet layout (navigation rail).
  static const double tablet = 900;

  /// Above [desktop]: large desktop layout (expanded sidebar).
  static const double desktop = 1200;

  /// Minimum allowed window width for desktop platforms.
  static const double minWindowWidth = 800;

  /// Minimum allowed window height for desktop platforms.
  static const double minWindowHeight = 600;

  /// Default window width on first launch.
  static const double defaultWindowWidth = 1280;

  /// Default window height on first launch.
  static const double defaultWindowHeight = 800;
}

/// Categorized device size derived from the current screen width.
enum DeviceSize { mobile, tablet, desktop }

extension BuildContextBreakpoints on BuildContext {
  /// Current screen width from [MediaQuery].
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Categorizes the screen width into a [DeviceSize] bucket.
  DeviceSize get deviceSize {
    final w = screenWidth;
    if (w < PilarBreakpoints.mobile) return DeviceSize.mobile;
    if (w < PilarBreakpoints.tablet) return DeviceSize.tablet;
    return DeviceSize.desktop;
  }

  bool get isMobile => deviceSize == DeviceSize.mobile;
  bool get isTablet => deviceSize == DeviceSize.tablet;
  bool get isDesktop => deviceSize == DeviceSize.desktop;
}
