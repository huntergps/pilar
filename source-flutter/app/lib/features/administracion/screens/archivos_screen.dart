// ArchivosScreen — Gestor Documental en el panel de Administración.
//
// Lista todos los adjuntos de la empresa con filtros y acciones.
// Patrón Odoo: Settings > Technical > Attachments.
//
// Responsive:
//   ≥ 600 px → SfDataGrid (columnas: tipo, nombre, tamaño, tags, fecha, acciones)
//   < 600 px → ListView de cards

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

import '../../../core/models/adjunto_model.dart';
import '../../../core/providers/adjuntos_provider.dart';
import '../../../core/services/storage_service.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ArchivosScreen extends ConsumerStatefulWidget {
  const ArchivosScreen({super.key});

  @override
  ConsumerState<ArchivosScreen> createState() => _ArchivosScreenState();
}

class _ArchivosScreenState extends ConsumerState<ArchivosScreen> {
  String? _filterTipo;
  String? _filterTag;
  String  _filterSearch = '';
  Timer?  _debounce;
  final   _searchCtrl   = TextEditingController();
  final   _tagCtrl      = TextEditingController();

  TodosAdjuntosParams get _params => (
        entidadTipo: _filterTipo,
        tag: _filterTag?.isEmpty == true ? null : _filterTag,
        search: _filterSearch.isEmpty ? null : _filterSearch,
      );

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _filterSearch = value.trim());
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme  = FluentTheme.of(context);
    final adjAsync = ref.watch(todosAdjuntosProvider(_params));

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Archivos'),
        commandBar: CommandBar(
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('Actualizar'),
              onPressed: () => ref.invalidate(todosAdjuntosProvider(_params)),
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Barra de filtros ----
            _FilterBar(
              searchCtrl: _searchCtrl,
              tagCtrl: _tagCtrl,
              filterTipo: _filterTipo,
              onSearch: _onSearchChanged,
              onTipoChanged: (v) => setState(() => _filterTipo = v),
              onTagChanged: (v) => setState(() => _filterTag = v),
              onClear: () {
                _searchCtrl.clear();
                _tagCtrl.clear();
                setState(() {
                  _filterTipo   = null;
                  _filterTag    = null;
                  _filterSearch = '';
                });
              },
            ),

            const SizedBox(height: 12),

            // ---- Contenido ----
            Expanded(
              child: adjAsync.when(
                loading: () => const Center(child: ProgressRing()),
                error: (e, _) => Center(
                  child: InfoBar(
                    title: Text('Error al cargar archivos: $e'),
                    severity: InfoBarSeverity.error,
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'Sin archivos',
                        style: theme.typography.body?.copyWith(
                          color: theme.resources.textFillColorSecondary,
                        ),
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (ctx, constraints) {
                      if (constraints.maxWidth >= 600) {
                        return _ArchivosGrid(
                          items: items,
                          onEliminar: (a) => _confirmarEliminar(context, a),
                        );
                      }
                      return _ArchivosList(
                        items: items,
                        onEliminar: (a) => _confirmarEliminar(context, a),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarEliminar(
      BuildContext ctx, AdjuntoItem adjunto) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => ContentDialog(
        title: const Text('Eliminar archivo'),
        content: Text(
          '¿Eliminar "${adjunto.nombre}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            child: const Text('Eliminar'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && ctx.mounted) {
      try {
        await Supabase.instance.client.rpc('eliminar_adjunto', params: {
          'p_adjunto_id': adjunto.id,
        });
        // ignore: use_build_context_synchronously
        ref.invalidate(todosAdjuntosProvider(_params));
      } catch (e) {
        if (ctx.mounted) {
          await displayInfoBar(
            ctx,
            builder: (_, close) => InfoBar(
              title: Text('Error al eliminar: $e'),
              severity: InfoBarSeverity.error,
              onClose: close,
            ),
          );
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Barra de filtros
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final TextEditingController tagCtrl;
  final String?       filterTipo;
  final ValueChanged<String>  onSearch;
  final ValueChanged<String?> onTipoChanged;
  final ValueChanged<String?> onTagChanged;
  final VoidCallback          onClear;

  const _FilterBar({
    required this.searchCtrl,
    required this.tagCtrl,
    required this.filterTipo,
    required this.onSearch,
    required this.onTipoChanged,
    required this.onTagChanged,
    required this.onClear,
  });

  static const _tipos = [
    'factura', 'contacto', 'empresa', 'orden_venta', 'orden_compra',
    'producto', 'empleado',
  ];

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        filterTipo != null || tagCtrl.text.isNotEmpty || searchCtrl.text.isNotEmpty;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Búsqueda por nombre
        SizedBox(
          width: 220,
          child: TextBox(
            controller: searchCtrl,
            placeholder: 'Buscar por nombre...',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(FluentIcons.search, size: 14),
            ),
            onChanged: onSearch,
          ),
        ),

        // Filtro por tipo de entidad
        ComboBox<String>(
          placeholder: const Text('Tipo de entidad'),
          value: filterTipo,
          items: _tipos
              .map((t) => ComboBoxItem(value: t, child: Text(t)))
              .toList(),
          onChanged: onTipoChanged,
        ),

        // Filtro por tag
        SizedBox(
          width: 160,
          child: TextBox(
            controller: tagCtrl,
            placeholder: 'Filtrar por tag...',
            onChanged: onTagChanged,
          ),
        ),

        // Limpiar filtros
        if (hasFilters)
          Button(
            onPressed: onClear,
            child: const Text('Limpiar filtros'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Vista SfDataGrid (≥ 600 px)
// ---------------------------------------------------------------------------

class _ArchivosGrid extends StatefulWidget {
  final List<AdjuntoItem> items;
  final ValueChanged<AdjuntoItem> onEliminar;

  const _ArchivosGrid({required this.items, required this.onEliminar});

  @override
  State<_ArchivosGrid> createState() => _ArchivosGridState();
}

class _ArchivosGridState extends State<_ArchivosGrid> {
  late _ArchivosDataSource _source;

  @override
  void initState() {
    super.initState();
    _source = _ArchivosDataSource(
      items: widget.items,
      onEliminar: widget.onEliminar,
    );
  }

  @override
  void didUpdateWidget(_ArchivosGrid old) {
    super.didUpdateWidget(old);
    if (old.items != widget.items) {
      _source = _ArchivosDataSource(
        items: widget.items,
        onEliminar: widget.onEliminar,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return SfDataGridTheme(
      data: SfDataGridThemeData(
        headerColor:
            theme.accentColor.withValues(alpha: 0.15),
      ),
      child: SfDataGrid(
        source: _source,
        columnWidthMode: ColumnWidthMode.fill,
        columns: [
          GridColumn(
            columnName: 'tipo',
            label: const _ColHeader('Tipo'),
            minimumWidth: 90,
            maximumWidth: 120,
          ),
          GridColumn(
            columnName: 'nombre',
            label: const _ColHeader('Nombre'),
            minimumWidth: 160,
          ),
          GridColumn(
            columnName: 'tamanio',
            label: const _ColHeader('Tamaño'),
            minimumWidth: 80,
            maximumWidth: 100,
          ),
          GridColumn(
            columnName: 'tags',
            label: const _ColHeader('Tags'),
            minimumWidth: 100,
          ),
          GridColumn(
            columnName: 'fecha',
            label: const _ColHeader('Fecha'),
            minimumWidth: 110,
            maximumWidth: 140,
          ),
          GridColumn(
            columnName: 'acciones',
            label: const _ColHeader(''),
            minimumWidth: 80,
            maximumWidth: 80,
          ),
        ],
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
      );
}

class _ArchivosDataSource extends DataGridSource {
  _ArchivosDataSource({
    required List<AdjuntoItem> items,
    required this.onEliminar,
  }) {
    _rows = items.map(_toRow).toList();
  }

  final ValueChanged<AdjuntoItem> onEliminar;
  late List<DataGridRow> _rows;

  @override
  List<DataGridRow> get rows => _rows;

  DataGridRow _toRow(AdjuntoItem a) => DataGridRow(cells: [
        DataGridCell(columnName: 'tipo',     value: a.entidadTipo),
        DataGridCell(columnName: 'nombre',   value: a.nombre),
        DataGridCell(columnName: 'tamanio',  value: a.tamanioLabel),
        DataGridCell(columnName: 'tags',     value: a.tags.join(', ')),
        DataGridCell(
          columnName: 'fecha',
          value: DateFormat('dd/MM/yy HH:mm').format(a.createdAt.toLocal()),
        ),
        DataGridCell(columnName: 'acciones', value: a),
      ]);

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final adjunto = row.getCells().last.value as AdjuntoItem;

    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        if (cell.columnName == 'acciones') {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Tooltip(
                message: 'Abrir',
                child: IconButton(
                  icon: const Icon(FluentIcons.open_in_new_window, size: 13),
                  onPressed: () => _openAdjunto(adjunto),
                ),
              ),
              Tooltip(
                message: 'Eliminar',
                child: IconButton(
                  icon: const Icon(FluentIcons.delete, size: 13),
                  onPressed: () => onEliminar(adjunto),
                ),
              ),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            cell.value.toString(),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _openAdjunto(AdjuntoItem a) async {
    final url = await StorageService.signedUrl(a.storagePath);
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}

// ---------------------------------------------------------------------------
// Vista ListView (< 600 px)
// ---------------------------------------------------------------------------

class _ArchivosList extends StatelessWidget {
  final List<AdjuntoItem> items;
  final ValueChanged<AdjuntoItem> onEliminar;

  const _ArchivosList({required this.items, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) => _ArchivoCard(
        adjunto: items[i],
        onEliminar: () => onEliminar(items[i]),
      ),
    );
  }
}

class _ArchivoCard extends StatelessWidget {
  final AdjuntoItem adjunto;
  final VoidCallback onEliminar;

  const _ArchivoCard({required this.adjunto, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    final theme     = FluentTheme.of(context);
    final dateLabel = DateFormat('dd/MM/yy').format(adjunto.createdAt.toLocal());

    return Card(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adjunto.nombre,
                  style: theme.typography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${adjunto.entidadTipo} · ${adjunto.tamanioLabel} · $dateLabel',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
                if (adjunto.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: adjunto.tags
                        .map((t) => _TagChip(tag: t))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(FluentIcons.open_in_new_window, size: 14),
            onPressed: () async {
              final url = await StorageService.signedUrl(adjunto.storagePath);
              if (url != null) {
                await launchUrl(
                    Uri.parse(url), mode: LaunchMode.externalApplication);
              }
            },
          ),
          IconButton(
            icon: Icon(FluentIcons.delete, size: 14, color: Colors.red),
            onPressed: onEliminar,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tag chip
// ---------------------------------------------------------------------------

class _TagChip extends StatelessWidget {
  final String tag;
  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tag,
        style: theme.typography.caption?.copyWith(
          color: theme.accentColor,
          fontSize: 10,
        ),
      ),
    );
  }
}

