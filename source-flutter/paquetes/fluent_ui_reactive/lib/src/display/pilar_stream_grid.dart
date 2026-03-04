import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluent_ui_reactive/src/core/pilar_async_builder.dart';
import 'package:fluent_ui_reactive/src/core/pilar_theme_ext.dart';
import 'package:fluent_ui_reactive/src/display/models.dart';

// ---------------------------------------------------------------------------
// Internal DataGridSource
// ---------------------------------------------------------------------------

/// Internal [DataGridSource] for [PilarStreamGrid].
///
/// Holds the item list and column definitions needed to build [DataGridRow]s
/// and [DataGridRowAdapter]s for Syncfusion's [SfDataGrid].
class _PilarDataGridSource<T> extends DataGridSource {
  _PilarDataGridSource({
    required List<T> items,
    required this.columns,
    required this.rowToMap,
  }) : _items = List<T>.from(items);

  /// Column definitions used to extract and format cell values.
  final List<PilarColumn> columns;

  /// Converts a data item into a key→value map for cell population.
  final Map<String, dynamic> Function(T) rowToMap;

  List<T> _items;

  // Cache built rows so they are not rebuilt on every [buildRow] call.
  List<DataGridRow> _cachedRows = [];

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Replaces the current item list and notifies the grid to rebuild.
  void updateItems(List<T> items) {
    _items = List<T>.from(items);
    _buildRows();
    notifyListeners();
  }

  /// Returns the original data item at [index], or null when out of range.
  T? getItemAtIndex(int index) {
    if (index < 0 || index >= _items.length) return null;
    return _items[index];
  }

  // -------------------------------------------------------------------------
  // DataGridSource overrides
  // -------------------------------------------------------------------------

  @override
  List<DataGridRow> get rows => _cachedRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    // Determine which original item corresponds to this row.
    final rowIndex = _cachedRows.indexOf(row);
    final item = rowIndex >= 0 && rowIndex < _items.length ? _items[rowIndex] : null;

    final cells = row.getCells();

    final cellWidgets = List<Widget>.generate(cells.length, (i) {
      final cell = cells[i];
      // Find the matching column definition by field name.
      final col = columns.firstWhere(
        (c) => c.field == cell.columnName,
        orElse: () => PilarColumn(field: cell.columnName, label: cell.columnName),
      );

      // Determine cell alignment based on format.
      final alignment = (col.format == ColumnFormat.currency ||
              col.format == ColumnFormat.integer)
          ? Alignment.centerRight
          : Alignment.centerLeft;

      Widget cellContent;
      if (col.cellBuilder != null) {
        cellContent = col.cellBuilder!(cell.value, item);
      } else {
        cellContent = Text(
          _formatValue(cell.value, col.format),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        );
      }

      return Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        child: cellContent,
      );
    });

    return DataGridRowAdapter(cells: cellWidgets);
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Builds [_cachedRows] from the current [_items] list.
  void _buildRows() {
    _cachedRows = _items.map((item) {
      final map = rowToMap(item);
      final cells = columns.map((col) {
        return DataGridCell<dynamic>(
          columnName: col.field,
          value: map[col.field],
        );
      }).toList();
      return DataGridRow(cells: cells);
    }).toList();
  }

  /// Formats [value] according to [format].
  ///
  /// - [ColumnFormat.text] → plain toString.
  /// - [ColumnFormat.currency] → "\$1,234.56" (en_US locale).
  /// - [ColumnFormat.date] → "dd/MM/yyyy".
  /// - [ColumnFormat.datetime] → "dd/MM/yyyy HH:mm".
  /// - [ColumnFormat.integer] → "1,234".
  /// - [ColumnFormat.boolean] → "✓" or "✗".
  String _formatValue(Object? value, ColumnFormat format) {
    if (value == null) return '';

    switch (format) {
      case ColumnFormat.text:
        return value.toString();

      case ColumnFormat.currency:
        final raw = double.tryParse(value.toString()) ?? 0.0;
        return NumberFormat.currency(
          symbol: '\$',
          decimalDigits: 2,
          locale: 'en_US',
        ).format(raw);

      case ColumnFormat.date:
        DateTime? dt;
        if (value is DateTime) {
          dt = value;
        } else {
          dt = DateTime.tryParse(value.toString());
        }
        return dt != null ? DateFormat('dd/MM/yyyy').format(dt) : value.toString();

      case ColumnFormat.datetime:
        DateTime? dt;
        if (value is DateTime) {
          dt = value;
        } else {
          dt = DateTime.tryParse(value.toString());
        }
        return dt != null ? DateFormat('dd/MM/yyyy HH:mm').format(dt) : value.toString();

      case ColumnFormat.integer:
        final raw = int.tryParse(value.toString()) ?? 0;
        return NumberFormat('#,##0').format(raw);

      case ColumnFormat.boolean:
        final truthy = value == true || value == 'true' || value == '1';
        return truthy ? '✓' : '✗';
    }
  }
}

// ---------------------------------------------------------------------------
// PilarStreamGrid
// ---------------------------------------------------------------------------

/// Reactive data grid that automatically updates when [AsyncValue<List<T>>]
/// changes.
///
/// Uses [SfDataGrid] from Syncfusion internally and applies a fluent_ui-
/// consistent theme via [PilarThemeExt.sfDataGridTheme].
///
/// ## Reactive pattern
///
/// ```dart
/// // 1. Expose a Brick stream through Riverpod
/// @riverpod
/// Stream<List<Factura>> facturas(Ref ref) =>
///     ref.watch(facturaRepoProvider).subscribe();
///
/// // 2. Pass the AsyncValue directly to PilarStreamGrid
/// class FacturasScreen extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     return PilarStreamGrid<Factura>(
///       value: ref.watch(facturasProvider),
///       columns: [
///         PilarColumn(field: 'numero',  label: 'Número'),
///         PilarColumn(field: 'total',   label: 'Total',  format: ColumnFormat.currency),
///         PilarColumn(field: 'fecha',   label: 'Fecha',  format: ColumnFormat.date),
///         PilarColumn(field: 'estado',  label: 'Estado',
///           cellBuilder: (v, row) => SriStatusBadge(estado: v as String)),
///       ],
///       rowToMap: (f) => {
///         'numero': f.numero,
///         'total':  f.total.toString(),
///         'fecha':  f.fecha,
///         'estado': f.estado,
///       },
///       onRowTap: (f) => context.push('/facturas/${f.id}'),
///     );
///   }
/// }
/// ```
///
/// When SQLite is updated via `repo.upsert()` → Brick emits a new list
/// → Riverpod [AsyncValue] updates → [PilarStreamGrid] rebuilds automatically.
/// No manual refresh or setState calls needed.
class PilarStreamGrid<T> extends StatefulWidget {
  /// Reactive data source. Typically from `ref.watch(someStreamProvider)`.
  final AsyncValue<List<T>> value;

  /// Column definitions — order determines grid column order.
  final List<PilarColumn> columns;

  /// Converts a data item into a field→value map for cell population.
  ///
  /// Keys must match [PilarColumn.field] values.
  final Map<String, dynamic> Function(T row) rowToMap;

  /// Called when the user taps a data row. Receives the original item.
  ///
  /// When null, row selection is disabled ([SelectionMode.none]).
  final void Function(T row)? onRowTap;

  /// Height of each data row in logical pixels. Defaults to 52.
  final double rowHeight;

  /// Height of the header row in logical pixels. Defaults to 56.
  final double headerRowHeight;

  /// Widget shown when the data list is empty.
  ///
  /// Defaults to a centered 'Sin registros' text.
  final Widget? emptyWidget;

  /// Widget shown while [value] is [AsyncLoading].
  ///
  /// Defaults to a centered [ProgressRing].
  final Widget? loadingWidget;

  /// Optional key passed to [SfDataGrid] to allow external access to its state
  /// (e.g., for export via `syncfusion_flutter_datagrid_export`).
  final GlobalKey<SfDataGridState>? dataGridKey;

  const PilarStreamGrid({
    super.key,
    required this.value,
    required this.columns,
    required this.rowToMap,
    this.onRowTap,
    this.rowHeight = 52.0,
    this.headerRowHeight = 56.0,
    this.emptyWidget,
    this.loadingWidget,
    this.dataGridKey,
  });

  @override
  State<PilarStreamGrid<T>> createState() => _PilarStreamGridState<T>();
}

class _PilarStreamGridState<T> extends State<PilarStreamGrid<T>> {
  late _PilarDataGridSource<T> _dataSource;

  @override
  void initState() {
    super.initState();
    _dataSource = _PilarDataGridSource<T>(
      items: widget.value.valueOrNull ?? const [],
      columns: widget.columns,
      rowToMap: widget.rowToMap,
    );
    // Build initial rows.
    _dataSource._buildRows();
  }

  @override
  void didUpdateWidget(covariant PilarStreamGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the AsyncValue reference changes and carries new data, push the
    // update into the DataGridSource so the grid rebuilds reactively.
    final newData = widget.value.valueOrNull;
    if (newData != null && widget.value != oldWidget.value) {
      _dataSource.updateItems(newData);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return PilarAsyncBuilder<List<T>>(
      value: widget.value,
      loadingWidget: widget.loadingWidget,
      emptyWidget: widget.emptyWidget,
      isEmpty: (list) => list.isEmpty,
      builder: (context, data) {
        return SfDataGridTheme(
          data: theme.sfDataGridTheme,
          child: SfDataGrid(
            key: widget.dataGridKey,
            source: _dataSource,
            columnWidthMode: ColumnWidthMode.fill,
            rowHeight: widget.rowHeight,
            headerRowHeight: widget.headerRowHeight,
            gridLinesVisibility: GridLinesVisibility.horizontal,
            headerGridLinesVisibility: GridLinesVisibility.none,
            selectionMode: widget.onRowTap != null
                ? SelectionMode.single
                : SelectionMode.none,
            onCellTap: widget.onRowTap != null
                ? (details) {
                    // rowIndex 0 is the header — skip it.
                    if (details.rowColumnIndex.rowIndex > 0) {
                      final item = _dataSource.getItemAtIndex(
                        details.rowColumnIndex.rowIndex - 1,
                      );
                      if (item != null) widget.onRowTap!(item);
                    }
                  }
                : null,
            columns: widget.columns.map((col) {
              return GridColumn(
                columnName: col.field,
                width: col.width ?? double.nan,
                label: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text(
                    col.label,
                    style: theme.typography.bodyStrong ?? theme.typography.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
