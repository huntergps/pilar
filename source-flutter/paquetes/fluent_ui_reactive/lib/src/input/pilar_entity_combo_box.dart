import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A reactive [ComboBox] whose item list is driven by a Riverpod [AsyncValue].
///
/// The items come from a [StreamProvider] that wraps Brick's `subscribe()`, so
/// whenever an entity is added, updated, or removed from local SQLite the
/// dropdown refreshes automatically — no manual refresh required.
///
/// ## States
///
/// | [items] state | Rendered widget |
/// |---|---|
/// | [AsyncLoading] | Disabled [ComboBox] with placeholder "Cargando..." + inline [ProgressRing] |
/// | [AsyncError] | Disabled [ComboBox] with placeholder "Error al cargar" + error icon |
/// | [AsyncData] | Enabled [ComboBox] with the entity list |
///
/// ## Example
///
/// ```dart
/// // Provider — defined once, usually in a providers file:
/// @riverpod
/// Stream<List<Cliente>> clientes(Ref ref) =>
///     ref.watch(clienteRepoProvider).subscribe();
///
/// // Widget — inside a ConsumerWidget or ConsumerStatefulWidget:
/// PilarEntityComboBox<Cliente>(
///   items: ref.watch(clientesProvider),
///   value: _selectedCliente,
///   displayText: (c) => '${c.nombre} (${c.ruc})',
///   onChanged: (c) => setState(() => _selectedCliente = c),
/// )
/// // When a new Cliente is upserted into SQLite → combo refreshes automatically.
/// ```
class PilarEntityComboBox<T> extends StatelessWidget {
  /// Reactive list of options — typically from a Riverpod [StreamProvider]
  /// wrapping Brick's `Repository.subscribe()`.
  final AsyncValue<List<T>> items;

  /// Currently selected value, or null when nothing is selected.
  final T? value;

  /// Called when the user picks a different item (or clears the selection).
  final void Function(T? value) onChanged;

  /// Converts an item to the string displayed inside the dropdown button and
  /// in the default list row.
  final String Function(T item) displayText;

  /// Text shown inside the button when [value] is null.
  ///
  /// Defaults to `'Seleccionar...'`.
  final String placeholder;

  /// Whether the combo box accepts user interaction.
  ///
  /// When `false`, [onChanged] is never called regardless of [items] state.
  final bool enabled;

  /// If `true` (the default) the combo box stretches to fill its parent's
  /// width constraint, matching the common ERP form layout.
  final bool isExpanded;

  /// When non-null, an [InfoLabel] wraps the combo box showing this message
  /// below the field, styled as an error.
  final String? errorMessage;

  /// Optional custom builder for each row inside the open dropdown.
  ///
  /// When null, each row is rendered as `Text(displayText(item))`.
  final Widget Function(T item)? itemBuilder;

  const PilarEntityComboBox({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.displayText,
    this.placeholder = 'Seleccionar...',
    this.enabled = true,
    this.isExpanded = true,
    this.errorMessage,
    this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return items.when(
      loading: _buildLoading,
      error: _buildError,
      data: (data) => _buildComboBox(context, data),
    );
  }

  /// Renders a disabled [ComboBox] with an inline [ProgressRing] while the
  /// entity list is being fetched from local SQLite for the first time.
  Widget _buildLoading() {
    return ComboBox<T>(
      placeholder: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Cargando...'),
          SizedBox(width: 8),
          SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
        ],
      ),
      onChanged: null,
      isExpanded: isExpanded,
      items: const [],
    );
  }

  /// Renders a disabled [ComboBox] indicating that the underlying stream
  /// encountered an error (e.g. SQLite corruption, Brick initialisation issue).
  Widget _buildError(Object err, StackTrace? _) {
    return ComboBox<T>(
      placeholder: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.error_badge, size: 16),
          SizedBox(width: 4),
          Text('Error al cargar'),
        ],
      ),
      onChanged: null,
      isExpanded: isExpanded,
      items: const [],
    );
  }

  /// Renders the fully interactive [ComboBox] once [data] is available.
  ///
  /// Wraps the widget in an [InfoLabel] when [errorMessage] is provided so
  /// that form validation messages appear inline.
  Widget _buildComboBox(BuildContext context, List<T> data) {
    final combo = ComboBox<T>(
      value: value,
      isExpanded: isExpanded,
      placeholder: Text(placeholder),
      onChanged: enabled ? onChanged : null,
      items: data.map((item) {
        return ComboBoxItem<T>(
          value: item,
          child: itemBuilder != null ? itemBuilder!(item) : Text(displayText(item)),
        );
      }).toList(),
    );

    if (errorMessage != null) {
      return InfoLabel(
        label: errorMessage!,
        labelStyle: TextStyle(
          color: FluentTheme.of(context).resources.systemFillColorCritical,
          fontSize: 12,
        ),
        child: combo,
      );
    }

    return combo;
  }
}
