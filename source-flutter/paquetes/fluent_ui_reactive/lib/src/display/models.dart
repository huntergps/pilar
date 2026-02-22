import 'package:fluent_ui/fluent_ui.dart';

/// Defines how a cell value is formatted in [PilarStreamGrid].
enum ColumnFormat {
  /// Plain text (default). Calls `.toString()`.
  text,

  /// Currency with 2 decimal places. Rendered as "\$1,234.56".
  /// Accepts [double], [int], [String], or [Decimal].
  currency,

  /// Date only. Rendered as "dd/MM/yyyy".
  /// Accepts [DateTime] or ISO 8601 [String].
  date,

  /// Date and time. Rendered as "dd/MM/yyyy HH:mm".
  /// Accepts [DateTime] or ISO 8601 [String].
  datetime,

  /// Integer with thousands separator. Rendered as "1,234".
  integer,

  /// Boolean rendered as "✓" (true) or "✗" (false/null).
  boolean,
}

/// Defines a column in [PilarStreamGrid].
class PilarColumn {
  /// Field name — must match a key returned by [PilarStreamGrid.rowToMap].
  final String field;

  /// Header label displayed in the column header row.
  final String label;

  /// Fixed column width in logical pixels.
  /// If null, the column participates in flexible [ColumnWidthMode.fill].
  final double? width;

  /// Format applied to the cell value. Defaults to [ColumnFormat.text].
  final ColumnFormat format;

  /// Custom cell widget builder. If provided, overrides [format].
  ///
  /// - [value]: the raw cell value from [PilarStreamGrid.rowToMap]
  /// - [row]: the original data item (cast to [T] at call site)
  ///
  /// Example:
  /// ```dart
  /// PilarColumn(
  ///   field: 'estado',
  ///   label: 'Estado',
  ///   cellBuilder: (value, row) => SriStatusBadge(estado: value as String),
  /// )
  /// ```
  final Widget Function(Object? value, dynamic row)? cellBuilder;

  const PilarColumn({
    required this.field,
    required this.label,
    this.width,
    this.format = ColumnFormat.text,
    this.cellBuilder,
  });
}

/// A data point for [PilarTimeSeriesChart].
class ChartPoint {
  /// X-axis value — typically a [DateTime] or category [String].
  final dynamic x;

  /// Y-axis numeric value.
  final double y;

  /// Optional label shown on the data point.
  final String? label;

  const ChartPoint({required this.x, required this.y, this.label});
}
