import 'package:fluent_ui/fluent_ui.dart';
import 'package:syncfusion_flutter_core/theme.dart';

/// Extensions on [FluentThemeData] for reactive widget theming.
///
/// Provides pre-configured Syncfusion theme objects that stay visually
/// consistent with the current fluent_ui theme and accent color.
extension PilarThemeExt on FluentThemeData {
  /// Accent color resolved for the current [brightness].
  ///
  /// Use this instead of [accentColor] directly to get the correct
  /// light/dark variant.
  Color get resolvedAccent => accentColor.defaultBrushFor(brightness);

  /// Pre-configured [SfDataGridThemeData] using current fluent_ui theme colors.
  ///
  /// Apply to [SfDataGridTheme.data] to keep Syncfusion grids consistent
  /// with the fluent_ui theme:
  ///
  /// ```dart
  /// SfDataGridTheme(
  ///   data: FluentTheme.of(context).sfDataGridTheme,
  ///   child: SfDataGrid(...),
  /// )
  /// ```
  SfDataGridThemeData get sfDataGridTheme => SfDataGridThemeData(
        headerColor: resolvedAccent.withValues(alpha: 0.15),
        headerHoverColor: resolvedAccent.withValues(alpha: 0.25),
        selectionColor: resolvedAccent.withValues(alpha: 0.12),
        rowHoverColor: brightness == Brightness.dark
            ? const Color(0xFF2D2D2D)
            : const Color(0xFFF8F8F8),
        gridLineColor: brightness == Brightness.dark
            ? const Color(0xFF3D3D3D)
            : const Color(0xFFE5E5E5),
        gridLineStrokeWidth: 0.5,
        frozenPaneLineColor: resolvedAccent.withValues(alpha: 0.3),
        frozenPaneLineWidth: 1.0,
      );
}
