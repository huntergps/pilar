import 'package:fluent_ui/fluent_ui.dart';

/// Una sección con título dentro de un [FormScaffold].
///
/// Agrupa campos relacionados con un encabezado y una línea divisoria.
/// Soporta layout en 1, 2 o 3 columnas vía [columns].
///
/// ### Ejemplo
/// ```dart
/// FormSection(
///   title: 'Información básica',
///   columns: 2,
///   children: [
///     PilarTextField(label: 'Nombre', ...),
///     PilarTextField(label: 'RUC/CI', ...),
///   ],
/// )
/// ```
class FormSection extends StatelessWidget {
  const FormSection({
    required this.children,
    super.key,
    this.title,
    this.columns = 1,
    this.columnSpacing = 16.0,
    this.rowSpacing = 12.0,
  }) : assert(columns >= 1 && columns <= 4, 'columns debe ser entre 1 y 4');

  /// Encabezado de la sección. Si es null, no se muestra título ni divisor.
  final String? title;

  /// Widgets de campo dentro de la sección.
  final List<Widget> children;

  /// Número de columnas para el layout de los campos (1–4). Por defecto: 1.
  ///
  /// Con [columns] > 1, los [children] se distribuyen en una grilla de columnas
  /// iguales. El último grupo puede quedar incompleto.
  final int columns;

  /// Espacio horizontal entre columnas. Por defecto: 16.
  final double columnSpacing;

  /// Espacio vertical entre filas. Por defecto: 12.
  final double rowSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: theme.typography.bodyStrong,
          ),
          const SizedBox(height: 6),
          Divider(
            style: DividerThemeData(
              thickness: 1,
              decoration: BoxDecoration(
                color: theme.resources.dividerStrokeColorDefault,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _buildFieldGrid(children),
      ],
    );
  }

  Widget _buildFieldGrid(List<Widget> fields) {
    if (columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < fields.length; i++) ...[
            fields[i],
            if (i < fields.length - 1) SizedBox(height: rowSpacing),
          ],
        ],
      );
    }

    // Build rows of `columns` items each
    final rows = <Widget>[];
    for (int i = 0; i < fields.length; i += columns) {
      final rowFields = fields.sublist(
        i,
        (i + columns).clamp(0, fields.length),
      );

      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int j = 0; j < rowFields.length; j++) ...[
              Expanded(child: rowFields[j]),
              if (j < rowFields.length - 1) SizedBox(width: columnSpacing),
            ],
            // Fill remaining slots with empty Expanded to keep alignment
            for (int j = rowFields.length; j < columns; j++) ...[
              SizedBox(width: columnSpacing),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      );

      if (i + columns < fields.length) {
        rows.add(SizedBox(height: rowSpacing));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
