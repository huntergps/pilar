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

  // --- PilarSizes shortcuts ---
  double get gridRowHeight => PilarSizes.gridRowHeight(deviceSize);
  double get bodyFontSize => PilarSizes.bodyFontSize(deviceSize);
  double get captionFontSize => PilarSizes.captionFontSize(deviceSize);
  double get buttonHeight => PilarSizes.buttonHeight(deviceSize);
  double get inputHeight => PilarSizes.inputHeight(deviceSize);
  double get navIconSize => PilarSizes.navIconSize(deviceSize);
  EdgeInsets get cardPadding => PilarSizes.cardPadding(deviceSize);
  double get contentPaddingH => PilarSizes.contentPaddingH(deviceSize);
}

/// Tamaños adaptativos por [DeviceSize] para consistencia visual en toda la app.
///
/// Garantiza que los elementos escalan correctamente en móvil, tablet y desktop
/// sin hardcodear valores en cada widget.
///
/// ### Uso directo
/// ```dart
/// SfDataGrid(rowHeight: PilarSizes.gridRowHeight(context.deviceSize))
/// ```
///
/// ### Uso via extensión BuildContext (más conciso)
/// ```dart
/// SfDataGrid(rowHeight: context.gridRowHeight)
/// ```
abstract final class PilarSizes {
  // -------------------------------------------------------------------------
  // DataGrid
  // -------------------------------------------------------------------------

  /// Altura de fila en SfDataGrid. Escala para touch en móvil/tablet.
  static double gridRowHeight(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 44.0,
        DeviceSize.tablet => 48.0,
        DeviceSize.desktop => 52.0,
      };

  /// Altura de cabecera en SfDataGrid.
  static double gridHeaderHeight(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 36.0,
        DeviceSize.tablet => 38.0,
        DeviceSize.desktop => 40.0,
      };

  // -------------------------------------------------------------------------
  // Tipografía
  // -------------------------------------------------------------------------

  /// Tamaño de fuente para texto body principal.
  static double bodyFontSize(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 13.0,
        DeviceSize.tablet => 13.0,
        DeviceSize.desktop => 14.0,
      };

  /// Tamaño de fuente para texto auxiliar / caption.
  static double captionFontSize(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 11.0,
        DeviceSize.tablet => 11.0,
        DeviceSize.desktop => 12.0,
      };

  /// Tamaño de fuente para subtítulos de sección.
  static double subtitleFontSize(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 15.0,
        DeviceSize.tablet => 15.0,
        DeviceSize.desktop => 16.0,
      };

  // -------------------------------------------------------------------------
  // Controles
  // -------------------------------------------------------------------------

  /// Altura mínima de botones (Button, FilledButton).
  static double buttonHeight(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 40.0,
        DeviceSize.tablet => 36.0,
        DeviceSize.desktop => 30.0,
      };

  /// Altura mínima de campos de texto (TextBox).
  static double inputHeight(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 44.0,
        DeviceSize.tablet => 38.0,
        DeviceSize.desktop => 32.0,
      };

  // -------------------------------------------------------------------------
  // Iconos
  // -------------------------------------------------------------------------

  /// Tamaño de iconos en ítems del NavigationPane.
  static double navIconSize(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 20.0,
        DeviceSize.tablet => 18.0,
        DeviceSize.desktop => 16.0,
      };

  /// Tamaño de iconos inline (dentro de texto o botones).
  static double inlineIconSize(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 16.0,
        DeviceSize.tablet => 14.0,
        DeviceSize.desktop => 14.0,
      };

  // -------------------------------------------------------------------------
  // Espaciado
  // -------------------------------------------------------------------------

  /// Padding interior de tarjetas (Card, ContentDialog sections).
  static EdgeInsets cardPadding(DeviceSize size) => switch (size) {
        DeviceSize.mobile => const EdgeInsets.all(12),
        DeviceSize.tablet => const EdgeInsets.all(14),
        DeviceSize.desktop => const EdgeInsets.all(16),
      };

  /// Padding horizontal de contenido principal de pantalla.
  static double contentPaddingH(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 12.0,
        DeviceSize.tablet => 16.0,
        DeviceSize.desktop => 24.0,
      };

  /// Padding vertical de contenido principal de pantalla.
  static double contentPaddingV(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 12.0,
        DeviceSize.tablet => 16.0,
        DeviceSize.desktop => 20.0,
      };

  /// Espaciado entre secciones de formulario.
  static double formSectionSpacing(DeviceSize size) => switch (size) {
        DeviceSize.mobile => 16.0,
        DeviceSize.tablet => 20.0,
        DeviceSize.desktop => 24.0,
      };
}
