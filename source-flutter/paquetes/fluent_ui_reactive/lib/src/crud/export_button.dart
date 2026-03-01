import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluent_ui_reactive/src/display/models.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import 'package:fluent_ui_reactive/src/crud/export_io.dart'
    if (dart.library.js_interop) 'package:fluent_ui_reactive/src/crud/export_web.dart'
    as platform_export;

/// Builds a [CommandBarBuilderItem] that exports data to CSV or Excel (.xlsx).
///
/// Returns a [CommandBarBuilderItem] that renders a button with a flyout
/// offering "Exportar CSV" and "Exportar Excel (.xlsx)" options.
///
/// ### Example
/// ```dart
/// CommandBar(
///   primaryItems: [
///     ExportButton.commandBarItem<Cliente>(
///       label: 'clientes',
///       items: clientes,
///       columns: [
///         PilarColumn(field: 'nombre', label: 'Nombre'),
///         PilarColumn(field: 'ruc', label: 'RUC'),
///       ],
///       rowToMap: (c) => {'nombre': c.nombre, 'ruc': c.ruc},
///     ),
///   ],
/// )
/// ```
///
/// Alternatively, use [ExportButton] directly as a widget in any layout.
class ExportButton<T> extends StatefulWidget {
  /// Creates an [ExportButton] widget.
  const ExportButton({
    required this.label,
    required this.items,
    required this.columns,
    required this.rowToMap,
    super.key,
  });

  /// File name without extension (e.g. "clientes").
  final String label;

  /// Current data items to export.
  final List<T> items;

  /// Column definitions used for headers.
  final List<PilarColumn> columns;

  /// Converts an item to a map of field -> value.
  final Map<String, dynamic> Function(T) rowToMap;

  /// Returns a [CommandBarBuilderItem] suitable for [CommandBar.primaryItems].
  static CommandBarBuilderItem commandBarItem<T>({
    required String label,
    required List<T> items,
    required List<PilarColumn> columns,
    required Map<String, dynamic> Function(T) rowToMap,
  }) {
    return CommandBarBuilderItem(
      builder: (context, displayMode, child) => ExportButton<T>(
        label: label,
        items: items,
        columns: columns,
        rowToMap: rowToMap,
      ),
      wrappedItem: CommandBarButton(
        icon: const Icon(FluentIcons.download),
        label: const Text('Exportar'),
        onPressed: () {},
      ),
    );
  }

  @override
  State<ExportButton<T>> createState() => _ExportButtonState<T>();
}

class _ExportButtonState<T> extends State<ExportButton<T>> {
  final _flyoutController = FlyoutController();
  bool _exporting = false;

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CSV generation
  // ---------------------------------------------------------------------------

  String _buildCsv() {
    final buf = StringBuffer();
    // Header row
    buf.writeln(
      widget.columns.map((c) => _escapeCsvField(c.label)).join(','),
    );
    // Data rows
    for (final item in widget.items) {
      final map = widget.rowToMap(item);
      buf.writeln(
        widget.columns
            .map((c) => _escapeCsvField(map[c.field]?.toString() ?? ''))
            .join(','),
      );
    }
    return buf.toString();
  }

  String _escapeCsvField(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // ---------------------------------------------------------------------------
  // Excel generation
  // ---------------------------------------------------------------------------

  List<int> _buildExcel() {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = widget.label;

    // Header style
    final headerStyle = workbook.styles.add('headerStyle');
    headerStyle.bold = true;

    // Headers
    for (var col = 0; col < widget.columns.length; col++) {
      final cell = sheet.getRangeByIndex(1, col + 1);
      cell.setText(widget.columns[col].label);
      cell.cellStyle = headerStyle;
    }

    // Data rows
    for (var row = 0; row < widget.items.length; row++) {
      final map = widget.rowToMap(widget.items[row]);
      for (var col = 0; col < widget.columns.length; col++) {
        final cell = sheet.getRangeByIndex(row + 2, col + 1);
        final value = map[widget.columns[col].field];
        if (value == null) {
          cell.setText('');
        } else if (value is num) {
          cell.setNumber(value.toDouble());
        } else if (value is DateTime) {
          cell.setDateTime(value);
        } else if (value is bool) {
          cell.setText(value ? 'S\u00ed' : 'No');
        } else {
          cell.setText(value.toString());
        }
      }
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Export actions
  // ---------------------------------------------------------------------------

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final csv = _buildCsv();
      final bytes = utf8.encode(csv);
      final fileName = '${widget.label}.csv';
      await platform_export.saveFile(fileName, bytes);
      if (mounted) {
        _showSuccess(fileName);
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    try {
      final bytes = _buildExcel();
      final fileName = '${widget.label}.xlsx';
      await platform_export.saveFile(fileName, bytes);
      if (mounted) {
        _showSuccess(fileName);
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSuccess(String fileName) {
    displayInfoBar(context, builder: (ctx, close) {
      return InfoBar(
        title: Text('Exportado: $fileName'),
        severity: InfoBarSeverity.success,
        onClose: close,
      );
    });
  }

  void _showError(String message) {
    displayInfoBar(context, builder: (ctx, close) {
      return InfoBar(
        title: const Text('Error al exportar'),
        content: Text(message),
        severity: InfoBarSeverity.error,
        onClose: close,
      );
    });
  }

  void _showFlyout() {
    _flyoutController.showFlyout(
      barrierDismissible: true,
      dismissOnPointerMoveAway: false,
      builder: (ctx) {
        return FlyoutContent(
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HoverButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _exportCsv();
                  },
                  builder: (ctx2, states) {
                    final theme = FluentTheme.of(ctx2);
                    return Container(
                      color: states.isHovered
                          ? theme.resources.subtleFillColorSecondary
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(FluentIcons.document,
                              size: 16, color: theme.inactiveColor),
                          const SizedBox(width: 10),
                          Text('Exportar CSV',
                              style: theme.typography.body),
                        ],
                      ),
                    );
                  },
                ),
                HoverButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _exportExcel();
                  },
                  builder: (ctx2, states) {
                    final theme = FluentTheme.of(ctx2);
                    return Container(
                      color: states.isHovered
                          ? theme.resources.subtleFillColorSecondary
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(FluentIcons.document,
                              size: 16, color: theme.inactiveColor),
                          const SizedBox(width: 10),
                          Text('Exportar Excel (.xlsx)',
                              style: theme.typography.body),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _flyoutController,
      child: IconButton(
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_exporting)
              const SizedBox(
                width: 16,
                height: 16,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.download, size: 16),
            const SizedBox(width: 6),
            const Text('Exportar'),
          ],
        ),
        onPressed: _exporting ? null : _showFlyout,
      ),
    );
  }
}
