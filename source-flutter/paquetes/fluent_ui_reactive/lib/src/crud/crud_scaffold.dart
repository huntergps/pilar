import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/src/display/pilar_stream_grid.dart';
import 'package:fluent_ui_reactive/src/display/models.dart';
import 'package:fluent_ui_reactive/src/core/pilar_async_builder.dart';

/// Scaffold de listado CRUD genérico para PILAR ERP.
///
/// Combina [ScaffoldPage] + [PageHeader] + [CommandBar] con acciones Nuevo,
/// Editar y Eliminar. El contenido usa [PilarStreamGrid] en pantallas ≥ 600px
/// y [ListView.separated] en pantallas menores.
///
/// ### Ejemplo
/// ```dart
/// CrudScaffold<Cliente>(
///   title: 'Clientes',
///   value: ref.watch(clientesProvider),
///   columns: [
///     PilarColumn(field: 'nombre', label: 'Nombre'),
///     PilarColumn(field: 'ruc',    label: 'RUC'),
///   ],
///   rowToMap: (c) => {'nombre': c.nombre, 'ruc': c.ruc},
///   onNew:    () => context.push('/clientes/nuevo'),
///   onRowTap: (c) => context.push('/clientes/${c.id}'),
///   onDelete: (c) async => ref.read(clienteRepoProvider).delete(c),
///   deleteConfirmText: (c) => '¿Eliminar a ${c.nombre}?',
///   showSearch: true,
///   searchFields: (c) => [c.nombre, c.ruc],
/// )
/// ```
///
/// ### Comportamiento
/// - Búsqueda local case-insensitive cuando [showSearch] es `true` y
///   [searchFields] devuelve los campos a filtrar.
/// - El tap en una fila del grid activa los botones Editar/Eliminar del
///   [CommandBar] y llama a [onRowTap] si está definido.
/// - La eliminación muestra un [ContentDialog] de confirmación antes de
///   ejecutar [onDelete].
/// - Los errores de eliminación se muestran como [InfoBar] dentro de la página.
class CrudScaffold<T> extends StatefulWidget {
  const CrudScaffold({
    required this.title,
    required this.value,
    required this.columns,
    required this.rowToMap,
    super.key,
    this.onNew,
    this.onRowTap,
    this.onDelete,
    this.canCreate = true,
    this.canEdit = true,
    this.canDelete = true,
    this.deleteConfirmText,
    this.extraActions,
    this.cardBuilder,
    this.showSearch = false,
    this.searchFields,
    this.searchPlaceholder = 'Buscar\u2026',
    this.emptyWidget,
  });

  /// Título de la pantalla.
  final String title;

  /// Fuente de datos reactiva. Normalmente `ref.watch(someStreamProvider)`.
  final AsyncValue<List<T>> value;

  /// Definiciones de columnas para [PilarStreamGrid] (≥ 600px).
  final List<PilarColumn> columns;

  /// Convierte un item en un mapa campo→valor para [PilarStreamGrid].
  final Map<String, dynamic> Function(T item) rowToMap;

  /// Callback al presionar "Nuevo". Si es `null` y [canCreate] es `true`,
  /// el botón no se muestra.
  final VoidCallback? onNew;

  /// Callback al tocar una fila (también activa los botones del CommandBar).
  final void Function(T item)? onRowTap;

  /// Callback asíncrono de eliminación. Si es `null`, el botón no se muestra.
  final Future<void> Function(T item)? onDelete;

  /// Controla la visibilidad del botón "Nuevo".
  final bool canCreate;

  /// Controla la visibilidad del botón "Editar" (requiere item seleccionado).
  final bool canEdit;

  /// Controla la visibilidad del botón "Eliminar" (requiere item seleccionado).
  final bool canDelete;

  /// Texto del [ContentDialog] de confirmación antes de eliminar.
  ///
  /// Si es `null`, se usa el texto genérico '¿Eliminar este registro?'.
  final String Function(T item)? deleteConfirmText;

  /// Acciones adicionales en el [CommandBar].
  final List<CommandBarItem>? extraActions;

  /// Builder para cards en modo móvil (< 600px).
  ///
  /// Si es `null`, se usa un fallback genérico que muestra el primer campo.
  final Widget Function(T item, bool isSelected)? cardBuilder;

  /// Si `true`, agrega un [TextBox] de búsqueda en el [CommandBar].
  final bool showSearch;

  /// Devuelve los campos de texto usados para filtrar localmente.
  ///
  /// Se requiere cuando [showSearch] es `true` para que la búsqueda funcione.
  final List<String> Function(T item)? searchFields;

  /// Placeholder del [TextBox] de búsqueda.
  final String searchPlaceholder;

  /// Widget mostrado cuando la lista está vacía.
  final Widget? emptyWidget;

  @override
  State<CrudScaffold<T>> createState() => _CrudScaffoldState<T>();
}

class _CrudScaffoldState<T> extends State<CrudScaffold<T>> {
  T? _selectedItem;
  bool _deleting = false;
  String? _deleteError;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  List<T> _applyFilter(List<T> items) {
    if (_searchQuery.isEmpty || widget.searchFields == null) return items;
    final query = _searchQuery.toLowerCase();
    return items.where((item) {
      final fields = widget.searchFields!(item);
      return fields.any((f) => f.toLowerCase().contains(query));
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  void _setSelected(T item) {
    setState(() => _selectedItem = item);
  }

  // ---------------------------------------------------------------------------
  // Delete flow
  // ---------------------------------------------------------------------------

  Future<void> _handleDelete(BuildContext context) async {
    if (_selectedItem == null || widget.onDelete == null) return;

    final item = _selectedItem;
    if (item == null) return;
    final theme = FluentTheme.of(context);

    final confirmText = widget.deleteConfirmText != null
        ? widget.deleteConfirmText!(item)
        : '\u00bfEliminar este registro? Esta acci\u00f3n no se puede deshacer.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        title: const Text('Confirmar eliminaci\u00f3n'),
        content: Text(confirmText),
        actions: [
          Button(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          Button(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(
                theme.resources.systemFillColorCritical,
              ),
              foregroundColor: WidgetStateProperty.all(Colors.white),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _deleting = true;
      _deleteError = null;
    });

    try {
      await widget.onDelete!(item);
      if (mounted) {
        setState(() {
          _selectedItem = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _deleteError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CommandBar items
  // ---------------------------------------------------------------------------

  List<CommandBarItem> _buildCommandItems(BuildContext context) {
    final items = <CommandBarItem>[];

    // Search box
    if (widget.showSearch) {
      items.add(
        CommandBarBuilderItem(
          builder: (ctx, displayMode, child) => SizedBox(
            width: 220,
            child: TextBox(
              controller: _searchCtrl,
              placeholder: widget.searchPlaceholder,
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(FluentIcons.search, size: 14),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          wrappedItem: CommandBarButton(
            icon: const Icon(FluentIcons.search),
            label: const Text('Buscar'),
            onPressed: () {},
          ),
        ),
      );
    }

    // New
    if (widget.onNew != null && widget.canCreate) {
      items.add(
        CommandBarButton(
          icon: const Icon(FluentIcons.add),
          label: const Text('Nuevo'),
          onPressed: widget.onNew,
        ),
      );
    }

    // Edit
    if (widget.canEdit && widget.onRowTap != null) {
      items.add(
        CommandBarButton(
          icon: const Icon(FluentIcons.edit),
          label: const Text('Editar'),
          onPressed: _selectedItem != null
              ? () {
                  final sel = _selectedItem;
                  if (sel != null) widget.onRowTap!(sel);
                }
              : null,
        ),
      );
    }

    // Delete
    if (widget.onDelete != null && widget.canDelete) {
      items.add(
        CommandBarButton(
          icon: const Icon(FluentIcons.delete),
          label: const Text('Eliminar'),
          onPressed: (_selectedItem != null && !_deleting)
              ? () => _handleDelete(context)
              : null,
        ),
      );
    }

    // Extra actions
    if (widget.extraActions != null) {
      items.addAll(widget.extraActions!);
    }

    return items;
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState(FluentThemeData theme) {
    return widget.emptyWidget ??
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.document, size: 48, color: theme.inactiveColor),
              const SizedBox(height: 12),
              Text('Sin registros', style: theme.typography.subtitle),
              const SizedBox(height: 8),
              Text(
                'Crea el primero con el bot\u00f3n Nuevo',
                style: theme.typography.body
                    ?.copyWith(color: theme.inactiveColor),
              ),
            ],
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // Card fallback for mobile
  // ---------------------------------------------------------------------------

  Widget _buildFallbackCard(
    BuildContext context,
    T item,
    bool isSelected,
    FluentThemeData theme,
  ) {
    final map = widget.rowToMap(item);
    final firstEntry = map.entries.isNotEmpty ? map.entries.first : null;

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? theme.accentColor.withValues(alpha: 0.1)
            : theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(
          color: isSelected
              ? theme.accentColor
              : theme.resources.controlStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(16),
      child: Text(
        firstEntry != null ? firstEntry.value?.toString() ?? '' : '',
        style: theme.typography.body,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Content (grid vs list)
  // ---------------------------------------------------------------------------

  Widget _buildDataContent(BuildContext context, List<T> items) {
    final theme = FluentTheme.of(context);

    if (items.isEmpty) return _buildEmptyState(theme);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        if (constraints.maxWidth >= 600) {
          // Desktop / tablet: PilarStreamGrid
          return PilarStreamGrid<T>(
            value: AsyncData(items),
            columns: widget.columns,
            rowToMap: widget.rowToMap,
            emptyWidget: _buildEmptyState(theme),
            onRowTap: (item) {
              _setSelected(item);
              widget.onRowTap?.call(item);
            },
          );
        }

        // Mobile: ListView + cards
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(size: 1),
          itemBuilder: (listCtx, index) {
            final item = items[index];
            final isSelected = _selectedItem != null &&
                identical(_selectedItem, item);

            final card = widget.cardBuilder != null
                ? widget.cardBuilder!(item, isSelected)
                : _buildFallbackCard(listCtx, item, isSelected, theme);

            return GestureDetector(
              onTap: () {
                _setSelected(item);
                widget.onRowTap?.call(item);
              },
              child: card,
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: PageHeader(
        title: Text(widget.title),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: _buildCommandItems(context),
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Delete error bar
          if (_deleteError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: InfoBar(
                title: const Text('Error al eliminar'),
                content: Text(_deleteError!),
                severity: InfoBarSeverity.error,
                onClose: () => setState(() => _deleteError = null),
              ),
            ),
          // Data area
          Expanded(
            child: PilarAsyncBuilder<List<T>>(
              value: widget.value,
              isEmpty: (list) => list.isEmpty,
              emptyWidget: _buildEmptyState(theme),
              builder: (ctx, data) {
                final filtered = _applyFilter(data);
                return _buildDataContent(ctx, filtered);
              },
            ),
          ),
        ],
      ),
    );
  }
}
