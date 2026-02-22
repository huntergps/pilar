import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/src/core/pilar_async_builder.dart';

/// Reactive list that automatically updates when [AsyncValue<List<T>>] changes.
///
/// Uses [ListView.separated] with fluent_ui styling.  An optional built-in
/// search field filters items client-side without any additional provider.
///
/// ## Reactive pattern
///
/// ```dart
/// // 1. Expose a Brick stream through Riverpod
/// @riverpod
/// Stream<List<Cliente>> clientes(Ref ref) =>
///     ref.watch(clienteRepoProvider).subscribe();
///
/// // 2. Use PilarStreamList in a ConsumerWidget
/// class ClientesScreen extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     return PilarStreamList<Cliente>(
///       value: ref.watch(clientesProvider),
///       searchable: true,
///       searchFields: (c) => [c.nombre, c.ruc],
///       itemBuilder: (context, cliente, index) => ListTile(
///         title: Text(cliente.nombre),
///         subtitle: Text(cliente.ruc),
///         onPressed: () => context.push('/clientes/${cliente.id}'),
///       ),
///     );
///   }
/// }
/// ```
///
/// When SQLite is updated via `repo.upsert()` → Brick emits a new list
/// → Riverpod [AsyncValue] updates → [PilarStreamList] rebuilds automatically.
/// No manual refresh or setState calls needed.
class PilarStreamList<T> extends StatefulWidget {
  /// Reactive data source. Typically from `ref.watch(someStreamProvider)`.
  final AsyncValue<List<T>> value;

  /// Called for each item in the (filtered) list.
  ///
  /// - [context]: the build context.
  /// - [item]: the data item for this position.
  /// - [index]: zero-based position in the filtered list.
  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  /// Optional custom separator between items.
  ///
  /// When null, a fluent_ui [Divider] is used.
  final Widget Function(BuildContext context, int index)? separatorBuilder;

  /// When true, a [TextBox] search field is shown above the list.
  ///
  /// Items are filtered client-side; [searchFields] must be provided.
  final bool searchable;

  /// Returns the list of strings to search within for a given item.
  ///
  /// Required when [searchable] is true. The search query is matched
  /// case-insensitively against each returned string.
  ///
  /// Example:
  /// ```dart
  /// searchFields: (cliente) => [cliente.nombre, cliente.ruc, cliente.email],
  /// ```
  final List<String> Function(T item)? searchFields;

  /// Placeholder text shown inside the search [TextBox].
  final String searchPlaceholder;

  /// Widget shown when the data list is empty (no items at all).
  ///
  /// Defaults to a centered 'Sin registros' text.
  final Widget? emptyWidget;

  /// Widget shown while [value] is [AsyncLoading].
  ///
  /// Defaults to a centered [ProgressRing].
  final Widget? loadingWidget;

  /// Padding applied around the list content.
  final EdgeInsetsGeometry? padding;

  const PilarStreamList({
    super.key,
    required this.value,
    required this.itemBuilder,
    this.separatorBuilder,
    this.searchable = false,
    this.searchFields,
    this.searchPlaceholder = 'Buscar...',
    this.emptyWidget,
    this.loadingWidget,
    this.padding,
  }) : assert(
          !searchable || searchFields != null,
          'searchFields must be provided when searchable is true.',
        );

  @override
  State<PilarStreamList<T>> createState() => _PilarStreamListState<T>();
}

class _PilarStreamListState<T> extends State<PilarStreamList<T>> {
  String _searchQuery = '';

  /// Filters [items] by [_searchQuery] when search is enabled.
  ///
  /// Returns the original list unchanged when [widget.searchable] is false
  /// or the query is empty.
  List<T> _filterItems(List<T> items) {
    if (!widget.searchable ||
        _searchQuery.isEmpty ||
        widget.searchFields == null) {
      return items;
    }

    final query = _searchQuery.toLowerCase();
    return items.where((item) {
      final fields = widget.searchFields!(item);
      return fields.any((field) => field.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PilarAsyncBuilder<List<T>>(
      value: widget.value,
      loadingWidget: widget.loadingWidget,
      emptyWidget: widget.emptyWidget,
      isEmpty: (list) => list.isEmpty,
      builder: (context, data) {
        final filtered = _filterItems(data);

        // Show a "no results" message when filtering eliminates all items.
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              'Sin resultados para "$_searchQuery"',
              style: FluentTheme.of(context).typography.body,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.searchable) ...[
              TextBox(
                placeholder: widget.searchPlaceholder,
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(FluentIcons.search),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8.0),
            ],
            Expanded(
              child: ListView.separated(
                padding: widget.padding,
                itemCount: filtered.length,
                itemBuilder: (context, index) =>
                    widget.itemBuilder(context, filtered[index], index),
                separatorBuilder: widget.separatorBuilder ??
                    (context, index) => const Divider(),
              ),
            ),
          ],
        );
      },
    );
  }
}
