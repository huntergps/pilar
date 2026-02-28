// ArchivosScreen — Gestor Documental completo en el panel de Administración.
//
// Features:
//   · Ver, abrir, eliminar (existentes)
//   · Subir desde esta pantalla (TUS resumable upload)
//   · Panel de detalle: renombrar, tags, descripción
//   · Sorting por columnas (client-side)
//   · Tags clickeables → aplican filtro
//
// Responsive:
//   ≥ 600 px → SfDataGrid (columnas: tipo, nombre, tamaño, tags, fecha, acciones)
//   < 600 px → ListView de cards

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

import '../../../core/models/adjunto_model.dart';
import '../../../core/providers/adjuntos_provider.dart';
import '../../../core/providers/empresa_provider.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/upload_service.dart';

// ---------------------------------------------------------------------------
// Tipos de entidad disponibles (compartido entre _FilterBar y upload dialog)
// ---------------------------------------------------------------------------

const _kTiposEntidad = [
  'empresa',
  'factura',
  'contacto',
  'orden_venta',
  'orden_compra',
  'producto',
  'empleado',
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ArchivosScreen extends ConsumerStatefulWidget {
  const ArchivosScreen({super.key});

  @override
  ConsumerState<ArchivosScreen> createState() => _ArchivosScreenState();
}

class _ArchivosScreenState extends ConsumerState<ArchivosScreen> {
  // Filter state
  String? _filterTipo;
  String? _filterTag;
  String  _filterSearch = '';
  Timer?  _debounce;
  final   _searchCtrl = TextEditingController();
  final   _tagCtrl    = TextEditingController();

  // Upload state
  bool               _isUploading   = false;
  UploadProgress?    _uploadProgress;
  UploadCancelToken? _cancelToken;

  // Sort state
  String? _sortColumn;    // 'nombre' | 'tamanio' | 'fecha' | null
  bool    _sortAscending = true;

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

  List<AdjuntoItem> _sortItems(List<AdjuntoItem> items) {
    if (_sortColumn == null) return items;
    final sorted = [...items];
    sorted.sort((a, b) {
      final int cmp;
      switch (_sortColumn) {
        case 'nombre':
          cmp = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
        case 'tamanio':
          cmp = a.tamanioBytes.compareTo(b.tamanioBytes);
        case 'fecha':
          cmp = a.createdAt.compareTo(b.createdAt);
        default:
          return 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn    = column;
        _sortAscending = true;
      }
    });
  }

  void _onTagFilter(String tag) {
    _tagCtrl.text = tag;
    setState(() => _filterTag = tag);
  }

  // ---------------------------------------------------------------------------
  // Ver (preview o abrir externamente) y Descargar
  // ---------------------------------------------------------------------------

  Future<void> _verAdjunto(AdjuntoItem adjunto) async {
    if (adjunto.iconCategory == 'image' || adjunto.iconCategory == 'pdf') {
      await _mostrarPrevia(adjunto);
    } else {
      final url = await StorageService.signedUrl(adjunto.storagePath);
      if (url != null && mounted) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _descargarAdjunto(AdjuntoItem adjunto) async {
    final url = await StorageService.signedUrl(adjunto.storagePath);
    if (url != null && mounted) {
      // Agrega disposition=attachment para forzar descarga en browsers
      final uri = Uri.parse(url).replace(
        queryParameters: {
          ...Uri.parse(url).queryParameters,
          'download': adjunto.nombre,
        },
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme    = FluentTheme.of(context);
    final adjAsync = ref.watch(todosAdjuntosProvider(_params));

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Archivos'),
        commandBar: CommandBar(
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.upload),
              label: const Text('Subir archivo'),
              onPressed: _isUploading ? null : _mostrarUploadDialog,
            ),
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
              searchCtrl:    _searchCtrl,
              tagCtrl:       _tagCtrl,
              filterTipo:    _filterTipo,
              onSearch:      _onSearchChanged,
              onTipoChanged: (v) => setState(() => _filterTipo = v),
              onTagChanged:  (v) => setState(() => _filterTag = v),
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

            // ---- Barra de progreso de upload ----
            if (_isUploading) ...[
              const SizedBox(height: 10),
              _UploadProgressBar(
                progress: _uploadProgress,
                onCancel: () => _cancelToken?.cancel(),
              ),
            ],

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
                  if (items.isEmpty && !_isUploading) {
                    return Center(
                      child: Text(
                        'Sin archivos',
                        style: theme.typography.body?.copyWith(
                          color: theme.resources.textFillColorSecondary,
                        ),
                      ),
                    );
                  }

                  final sorted = _sortItems(items);

                  return LayoutBuilder(
                    builder: (ctx, constraints) {
                      if (constraints.maxWidth >= 600) {
                        return _ArchivosGrid(
                          items:         sorted,
                          sortColumn:    _sortColumn,
                          sortAscending: _sortAscending,
                          onSort:        _onSort,
                          onDetalle:     _mostrarDetalle,
                          onEliminar:    (a) => _confirmarEliminar(context, a),
                          onVer:         _verAdjunto,
                          onDescargar:   _descargarAdjunto,
                          onTagFilter:   (_, tag) => _onTagFilter(tag),
                        );
                      }
                      return _ArchivosList(
                        items:       sorted,
                        onEliminar:  (a) => _confirmarEliminar(context, a),
                        onDetalle:   _mostrarDetalle,
                        onVer:       _verAdjunto,
                        onDescargar: _descargarAdjunto,
                        onTagTap:    _onTagFilter,
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

  // ---------------------------------------------------------------------------
  // Eliminar
  // ---------------------------------------------------------------------------

  Future<void> _confirmarEliminar(
      BuildContext ctx, AdjuntoItem adjunto) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => ContentDialog(
        title: const Text('Eliminar archivo'),
        content: Text(
          '¿Eliminar "${adjunto.nombre}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(dctx, false),
          ),
          FilledButton(
            child: const Text('Eliminar'),
            onPressed: () => Navigator.pop(dctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client.rpc('eliminar_adjunto', params: {
          'p_adjunto_id': adjunto.id,
        });
        ref.invalidate(todosAdjuntosProvider(_params));
      } catch (e) {
        if (mounted) {
          await displayInfoBar(
            context,
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

  // ---------------------------------------------------------------------------
  // Vista previa (imagen / PDF)
  // ---------------------------------------------------------------------------

  Future<void> _mostrarPrevia(AdjuntoItem adjunto) async {
    final url = await StorageService.signedUrl(adjunto.storagePath);
    if (url == null || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PreviaDialog(adjunto: adjunto, url: url),
    );
  }

  // ---------------------------------------------------------------------------
  // Panel de detalle / edición
  // ---------------------------------------------------------------------------

  Future<void> _mostrarDetalle(AdjuntoItem adjunto) async {
    final nombreCtrl      = TextEditingController(text: adjunto.nombre);
    final descripcionCtrl = TextEditingController(text: adjunto.descripcion ?? '');
    final newTagCtrl      = TextEditingController();
    var   currentTags     = List<String>.from(adjunto.tags);
    var   isSaving        = false;

    await showDialog<void>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dialogCtx, setDlg) {
          final theme = FluentTheme.of(dialogCtx);

          return ContentDialog(
            title: Row(
              children: [
                _FileIcon(
                  category: adjunto.iconCategory,
                  ext: adjunto.extension,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Detalle del archivo')),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre
                    TextBox(
                      controller: nombreCtrl,
                      placeholder: 'Nombre del archivo',
                    ),
                    const SizedBox(height: 12),

                    // Metadatos readonly
                    _MetadataRow(adjunto: adjunto),
                    const SizedBox(height: 12),

                    // Tags
                    Text('Etiquetas', style: theme.typography.bodyStrong),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ...currentTags.map((t) => _RemovableTagChip(
                              tag: t,
                              onRemove: () => setDlg(
                                () => currentTags = List.from(currentTags)
                                  ..remove(t),
                              ),
                            )),
                        SizedBox(
                          width: 130,
                          child: TextBox(
                            controller: newTagCtrl,
                            placeholder: 'Nueva tag...',
                            suffix: IconButton(
                              icon: const Icon(FluentIcons.add, size: 12),
                              onPressed: () {
                                final tag = newTagCtrl.text.trim();
                                if (tag.isNotEmpty &&
                                    !currentTags.contains(tag)) {
                                  setDlg(() {
                                    currentTags = [...currentTags, tag];
                                    newTagCtrl.clear();
                                  });
                                }
                              },
                            ),
                            onSubmitted: (v) {
                              final tag = v.trim();
                              if (tag.isNotEmpty &&
                                  !currentTags.contains(tag)) {
                                setDlg(() {
                                  currentTags = [...currentTags, tag];
                                  newTagCtrl.clear();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Descripción
                    Text('Descripción', style: theme.typography.bodyStrong),
                    const SizedBox(height: 6),
                    TextBox(
                      controller: descripcionCtrl,
                      placeholder: 'Descripción opcional...',
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              Row(
                children: [
                  // Eliminar
                  Button(
                    onPressed: isSaving
                        ? null
                        : () {
                            Navigator.pop(dctx);
                            _confirmarEliminar(context, adjunto);
                          },
                    child: Text(
                      'Eliminar',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  const Spacer(),
                  // Cancelar
                  Button(
                    onPressed:
                        isSaving ? null : () => Navigator.pop(dctx),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  // Guardar
                  FilledButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setDlg(() => isSaving = true);
                            try {
                              final client = Supabase.instance.client;

                              // Renombrar si cambió
                              final newName = nombreCtrl.text.trim();
                              if (newName.isNotEmpty &&
                                  newName != adjunto.nombre) {
                                await client
                                    .rpc('renombrar_adjunto', params: {
                                  'p_adjunto_id': adjunto.id,
                                  'p_nombre': newName,
                                });
                              }

                              // Tags diff
                              final oldSet =
                                  Set<String>.from(adjunto.tags);
                              final newSet =
                                  Set<String>.from(currentTags);
                              for (final t in newSet.difference(oldSet)) {
                                await client.rpc('agregar_tag_adjunto',
                                    params: {
                                      'p_adjunto_id': adjunto.id,
                                      'p_tag': t,
                                    });
                              }
                              for (final t in oldSet.difference(newSet)) {
                                await client.rpc('quitar_tag_adjunto',
                                    params: {
                                      'p_adjunto_id': adjunto.id,
                                      'p_tag': t,
                                    });
                              }

                              // Descripción si cambió
                              final newDesc =
                                  descripcionCtrl.text.trim();
                              final oldDesc =
                                  adjunto.descripcion ?? '';
                              if (newDesc != oldDesc) {
                                await client.rpc(
                                    'actualizar_descripcion_adjunto',
                                    params: {
                                      'p_adjunto_id': adjunto.id,
                                      'p_descripcion': newDesc.isEmpty
                                          ? null
                                          : newDesc,
                                    });
                              }

                              if (dctx.mounted) Navigator.pop(dctx);
                              ref.invalidate(
                                  todosAdjuntosProvider(_params));
                            } catch (e) {
                              setDlg(() => isSaving = false);
                              if (mounted) {
                                displayInfoBar(
                                  context,
                                  builder: (_, close) => InfoBar(
                                    title:
                                        Text('Error al guardar: $e'),
                                    severity: InfoBarSeverity.error,
                                    onClose: close,
                                  ),
                                );
                              }
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: ProgressRing(strokeWidth: 2),
                          )
                        : const Text('Guardar'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    nombreCtrl.dispose();
    descripcionCtrl.dispose();
    newTagCtrl.dispose();
  }

  // ---------------------------------------------------------------------------
  // Upload desde ArchivosScreen
  // ---------------------------------------------------------------------------

  /// Busca registros en la tabla correspondiente al tipo de entidad.
  /// Retorna lista de {id, nombre}. Si la tabla no existe, retorna [].
  Future<List<Map<String, dynamic>>> _searchEntidad(
      String tipo, String query, String empresaId) async {
    const tableMap = {
      'contacto': ('contactos', 'nombre_completo'),
      'producto': ('productos', 'nombre'),
      'factura': ('facturas', 'numero'),
      'orden_venta': ('ordenes_venta', 'numero'),
      'orden_compra': ('ordenes_compra', 'numero'),
      'empleado': ('empleados', 'nombre_completo'),
    };
    final info = tableMap[tipo];
    if (info == null) return [];
    final (tableName, nameField) = info;
    try {
      final rows = await Supabase.instance.client
          .from(tableName)
          .select('id, $nameField')
          .eq('empresa_id', empresaId)
          .ilike(nameField, '%$query%')
          .limit(10);
      return (rows as List).map((r) => {
            'id': r['id'] as String,
            'nombre': r[nameField]?.toString() ?? r['id'] as String,
          }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _mostrarUploadDialog() async {
    final empresaId = ref.read(empresaActivaIdProvider);
    if (empresaId == null) return;

    PlatformFile?                     selectedFile;
    String                            selectedTipo      = 'empresa';
    String?                           selectedEntidadId = empresaId;
    List<AutoSuggestBoxItem<String>>  entidadItems      = [];
    final entidadCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dialogCtx, setDlg) {
          final needsSearch = selectedTipo != 'empresa';
          final canConfirm  = selectedFile != null;

          return ContentDialog(
            title: const Text('Subir archivo'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Tipo de entidad ----
                  const Text('Asociar a'),
                  const SizedBox(height: 4),
                  ComboBox<String>(
                    value: selectedTipo,
                    isExpanded: true,
                    items: _kTiposEntidad
                        .map((t) => ComboBoxItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setDlg(() {
                      selectedTipo = v ?? 'empresa';
                      entidadCtrl.clear();
                      entidadItems = [];
                      if (selectedTipo == 'empresa') {
                        selectedEntidadId = empresaId;
                      } else {
                        selectedEntidadId = null;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),

                  // ---- Buscador de entidad (solo cuando no es empresa) ----
                  if (needsSearch) ...[
                    Text('Buscar $selectedTipo'),
                    const SizedBox(height: 4),
                    AutoSuggestBox<String>(
                      controller: entidadCtrl,
                      placeholder: 'Escribe para buscar...',
                      items: entidadItems,
                      onChanged: (text, reason) async {
                        if (text.length < 2) return;
                        final rows = await _searchEntidad(
                            selectedTipo, text, empresaId);
                        setDlg(() {
                          selectedEntidadId = null;
                          entidadItems = rows
                              .map((r) => AutoSuggestBoxItem<String>(
                                    value: r['id'] as String,
                                    label: r['nombre'] as String,
                                  ))
                              .toList();
                        });
                      },
                      onSelected: (item) {
                        setDlg(() => selectedEntidadId = item.value);
                      },
                    ),
                    if (selectedEntidadId == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Selecciona un registro o el archivo se asociará a la empresa.',
                          style: TextStyle(
                              fontSize: 11,
                              color: FluentTheme.of(dialogCtx).inactiveColor),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],

                  // ---- Selector de archivo ----
                  Row(
                    children: [
                      Button(
                        child: const Text('Elegir archivo'),
                        onPressed: () async {
                          final f = await UploadService.pickFile();
                          if (f != null) setDlg(() => selectedFile = f);
                        },
                      ),
                      if (selectedFile != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selectedFile!.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              Button(
                child: const Text('Cancelar'),
                onPressed: () => Navigator.pop(dctx, false),
              ),
              FilledButton(
                onPressed: canConfirm ? () => Navigator.pop(dctx, true) : null,
                child: const Text('Subir'),
              ),
            ],
          );
        },
      ),
    );

    final file      = selectedFile;
    final tipo      = selectedTipo;
    // Si no se seleccionó entidad específica, cae en empresa
    final entidadId = selectedEntidadId ?? empresaId;
    final tipoFinal = selectedEntidadId != null ? tipo : 'empresa';
    entidadCtrl.dispose();

    if (confirmed != true || file == null) return;

    // Iniciar upload
    final token = UploadCancelToken();
    if (!mounted) return;
    setState(() {
      _isUploading    = true;
      _uploadProgress = null;
      _cancelToken    = token;
    });

    try {
      final progressCtrl = StreamController<UploadProgress>();
      final sub = progressCtrl.stream.listen((p) {
        if (mounted) setState(() => _uploadProgress = p);
      });

      final result = await UploadService.uploadResumable(
        file:               file,
        empresaId:          empresaId,
        entidadTipo:        tipoFinal,
        entidadId:          entidadId,
        progressController: progressCtrl,
        cancelToken:        token,
      );

      await progressCtrl.close();
      await sub.cancel();

      await Supabase.instance.client.rpc('registrar_adjunto', params: {
        'p_empresa_id'      : empresaId,
        'p_entidad_tipo'    : tipoFinal,
        'p_entidad_id'      : entidadId,
        'p_nombre'          : result.nombreOriginal,
        'p_nombre_original' : result.nombreOriginal,
        'p_mime_type'       : result.mimeType,
        'p_tamanio_bytes'   : result.tamanioBytes,
        'p_storage_path'    : result.storagePath,
      });

      if (mounted) ref.invalidate(todosAdjuntosProvider(_params));
    } on UploadException catch (e) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (_, close) => InfoBar(
            title: Text(e.message),
            severity: InfoBarSeverity.warning,
            onClose: close,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (_, close) => InfoBar(
            title: Text('Error al subir: $e'),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading    = false;
          _uploadProgress = null;
          _cancelToken    = null;
        });
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
          items: _kTiposEntidad
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
  final List<AdjuntoItem>              items;
  final String?                        sortColumn;
  final bool                           sortAscending;
  final ValueChanged<AdjuntoItem>      onDetalle;
  final ValueChanged<AdjuntoItem>      onEliminar;
  final ValueChanged<AdjuntoItem>      onVer;
  final ValueChanged<AdjuntoItem>      onDescargar;
  final void Function(String)          onSort;
  final void Function(AdjuntoItem, String) onTagFilter;

  const _ArchivosGrid({
    required this.items,
    required this.sortColumn,
    required this.sortAscending,
    required this.onDetalle,
    required this.onEliminar,
    required this.onVer,
    required this.onDescargar,
    required this.onSort,
    required this.onTagFilter,
  });

  @override
  State<_ArchivosGrid> createState() => _ArchivosGridState();
}

class _ArchivosGridState extends State<_ArchivosGrid> {
  late _ArchivosDataSource _source;

  @override
  void initState() {
    super.initState();
    _source = _ArchivosDataSource(
      items:       widget.items,
      onEliminar:  widget.onEliminar,
      onDetalle:   widget.onDetalle,
      onVer:       widget.onVer,
      onDescargar: widget.onDescargar,
      onTagFilter: widget.onTagFilter,
    );
  }

  @override
  void didUpdateWidget(_ArchivosGrid old) {
    super.didUpdateWidget(old);
    if (old.items != widget.items) {
      _source = _ArchivosDataSource(
        items:       widget.items,
        onEliminar:  widget.onEliminar,
        onDetalle:   widget.onDetalle,
        onVer:       widget.onVer,
        onDescargar: widget.onDescargar,
        onTagFilter: widget.onTagFilter,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final sc    = widget.sortColumn;
    final asc   = widget.sortAscending;

    return SfDataGridTheme(
      data: SfDataGridThemeData(
        headerColor: theme.accentColor.withValues(alpha: 0.15),
      ),
      child: SfDataGrid(
        source:           _source,
        columnWidthMode:  ColumnWidthMode.fill,
        rowHeight: 44,
        columns: [
          GridColumn(
            columnName: 'tipo',
            label: const _ColHeader('Tipo'),
            minimumWidth: 90,
            maximumWidth: 120,
          ),
          GridColumn(
            columnName: 'nombre',
            label: _SortableColHeader(
              text:       'Nombre',
              columnName: 'nombre',
              sortColumn: sc,
              ascending:  asc,
              onSort:     widget.onSort,
            ),
            minimumWidth: 160,
          ),
          GridColumn(
            columnName: 'tamanio',
            label: _SortableColHeader(
              text:       'Tamaño',
              columnName: 'tamanio',
              sortColumn: sc,
              ascending:  asc,
              onSort:     widget.onSort,
            ),
            minimumWidth: 80,
            maximumWidth: 110,
          ),
          GridColumn(
            columnName: 'tags',
            label: const _ColHeader('Tags'),
            minimumWidth: 100,
          ),
          GridColumn(
            columnName: 'fecha',
            label: _SortableColHeader(
              text:       'Fecha',
              columnName: 'fecha',
              sortColumn: sc,
              ascending:  asc,
              onSort:     widget.onSort,
            ),
            minimumWidth: 110,
            maximumWidth: 140,
          ),
          GridColumn(
            columnName: 'acciones',
            label: const _ColHeader(''),
            minimumWidth: 152,
            maximumWidth: 152,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column headers
// ---------------------------------------------------------------------------

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      );
}

class _SortableColHeader extends StatelessWidget {
  final String  text;
  final String  columnName;
  final String? sortColumn;
  final bool    ascending;
  final void Function(String) onSort;

  const _SortableColHeader({
    required this.text,
    required this.columnName,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = sortColumn == columnName;
    final icon = isActive
        ? (ascending ? FluentIcons.sort_up : FluentIcons.sort_down)
        : FluentIcons.sort;

    return GestureDetector(
      onTap: () => onSort(columnName),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isActive
                    ? FluentTheme.of(context).accentColor
                    : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 4),
            Icon(
              icon,
              size: 11,
              color: isActive
                  ? FluentTheme.of(context).accentColor
                  : FluentTheme.of(context).resources.textFillColorSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DataSource
// ---------------------------------------------------------------------------

class _ArchivosDataSource extends DataGridSource {
  _ArchivosDataSource({
    required List<AdjuntoItem>            items,
    required this.onEliminar,
    required this.onDetalle,
    required this.onVer,
    required this.onDescargar,
    required this.onTagFilter,
  }) {
    _rows = items.map(_toRow).toList();
  }

  final ValueChanged<AdjuntoItem>           onEliminar;
  final ValueChanged<AdjuntoItem>           onDetalle;
  final ValueChanged<AdjuntoItem>           onVer;
  final ValueChanged<AdjuntoItem>           onDescargar;
  final void Function(AdjuntoItem, String)  onTagFilter;
  late  List<DataGridRow>                   _rows;

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
        switch (cell.columnName) {
          case 'acciones':
            final isPreviewable = adjunto.iconCategory == 'image' ||
                adjunto.iconCategory == 'pdf';
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Tooltip(
                  message: isPreviewable ? 'Vista previa' : 'Abrir',
                  child: IconButton(
                    icon: Icon(
                      isPreviewable
                          ? FluentIcons.preview
                          : FluentIcons.open_in_new_window,
                      size: 13,
                    ),
                    onPressed: () => onVer(adjunto),
                  ),
                ),
                Tooltip(
                  message: 'Descargar',
                  child: IconButton(
                    icon: const Icon(FluentIcons.download, size: 13),
                    onPressed: () => onDescargar(adjunto),
                  ),
                ),
                Tooltip(
                  message: 'Detalles',
                  child: IconButton(
                    icon: const Icon(FluentIcons.side_panel, size: 13),
                    onPressed: () => onDetalle(adjunto),
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

          case 'tags':
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: adjunto.tags.isEmpty
                  ? const SizedBox.shrink()
                  : Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: adjunto.tags
                          .map((t) => _ClickableTagChip(
                                tag: t,
                                onTap: () => onTagFilter(adjunto, t),
                              ))
                          .toList(),
                    ),
            );

          default:
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                cell.value.toString(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            );
        }
      }).toList(),
    );
  }

}

// ---------------------------------------------------------------------------
// Vista ListView (< 600 px)
// ---------------------------------------------------------------------------

class _ArchivosList extends StatelessWidget {
  final List<AdjuntoItem>           items;
  final ValueChanged<AdjuntoItem>   onEliminar;
  final ValueChanged<AdjuntoItem>   onDetalle;
  final ValueChanged<AdjuntoItem>   onVer;
  final ValueChanged<AdjuntoItem>   onDescargar;
  final ValueChanged<String>        onTagTap;

  const _ArchivosList({
    required this.items,
    required this.onEliminar,
    required this.onDetalle,
    required this.onVer,
    required this.onDescargar,
    required this.onTagTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) => _ArchivoCard(
        adjunto:     items[i],
        onEliminar:  () => onEliminar(items[i]),
        onDetalle:   () => onDetalle(items[i]),
        onVer:       () => onVer(items[i]),
        onDescargar: () => onDescargar(items[i]),
        onTagTap:    onTagTap,
      ),
    );
  }
}

class _ArchivoCard extends StatelessWidget {
  final AdjuntoItem      adjunto;
  final VoidCallback     onEliminar;
  final VoidCallback     onDetalle;
  final VoidCallback     onVer;
  final VoidCallback     onDescargar;
  final ValueChanged<String> onTagTap;

  const _ArchivoCard({
    required this.adjunto,
    required this.onEliminar,
    required this.onDetalle,
    required this.onVer,
    required this.onDescargar,
    required this.onTagTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme     = FluentTheme.of(context);
    final dateLabel = DateFormat('dd/MM/yy').format(adjunto.createdAt.toLocal());
    final isPreviewable = adjunto.iconCategory == 'image' ||
        adjunto.iconCategory == 'pdf';

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
                        .map((t) => _ClickableTagChip(
                              tag: t,
                              onTap: () => onTagTap(t),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          Tooltip(
            message: isPreviewable ? 'Vista previa' : 'Abrir',
            child: IconButton(
              icon: Icon(
                isPreviewable
                    ? FluentIcons.preview
                    : FluentIcons.open_in_new_window,
                size: 14,
              ),
              onPressed: onVer,
            ),
          ),
          Tooltip(
            message: 'Descargar',
            child: IconButton(
              icon: const Icon(FluentIcons.download, size: 14),
              onPressed: onDescargar,
            ),
          ),
          Tooltip(
            message: 'Detalles',
            child: IconButton(
              icon: const Icon(FluentIcons.side_panel, size: 14),
              onPressed: onDetalle,
            ),
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
// Tag chips
// ---------------------------------------------------------------------------


/// Tag chip clickeable — aplica filtro por tag.
class _ClickableTagChip extends StatelessWidget {
  final String    tag;
  final VoidCallback onTap;

  const _ClickableTagChip({required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }
}

/// Tag chip con botón X para eliminar (en panel de detalle).
class _RemovableTagChip extends StatelessWidget {
  final String     tag;
  final VoidCallback onRemove;

  const _RemovableTagChip({required this.tag, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 4, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag,
            style: theme.typography.caption?.copyWith(
              color: theme.accentColor,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(FluentIcons.cancel, size: 10, color: theme.accentColor),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de progreso de upload (copiada de adjuntos_panel.dart)
// ---------------------------------------------------------------------------

class _UploadProgressBar extends StatelessWidget {
  final UploadProgress? progress;
  final VoidCallback?   onCancel;

  const _UploadProgressBar({required this.progress, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final p     = progress;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FluentIcons.cloud_upload, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p != null ? 'Subiendo: ${p.label}' : 'Preparando upload…',
                  style: theme.typography.caption,
                ),
              ),
              if (onCancel != null)
                IconButton(
                  icon: const Icon(FluentIcons.cancel, size: 12),
                  onPressed: onCancel,
                ),
            ],
          ),
          const SizedBox(height: 6),
          ProgressBar(value: p != null ? p.fraction * 100 : null),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ícono de archivo (copiado de adjuntos_panel.dart)
// ---------------------------------------------------------------------------

class _FileIcon extends StatelessWidget {
  final String category;
  final String ext;

  const _FileIcon({required this.category, required this.ext});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = _colorFor(category, theme);

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          ext.length > 4 ? ext.substring(0, 4) : ext,
          style: theme.typography.caption?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Color _colorFor(String cat, FluentThemeData theme) {
    switch (cat) {
      case 'image': return Colors.green;
      case 'pdf':   return Colors.red;
      case 'word':  return Colors.blue;
      case 'excel': return const Color(0xFF217346);
      case 'ppt':   return Colors.orange;
      case 'csv':   return Colors.teal;
      case 'zip':   return Colors.purple;
      default:      return theme.accentColor;
    }
  }
}

// ---------------------------------------------------------------------------
// Metadatos del archivo en el panel de detalle
// ---------------------------------------------------------------------------

class _MetadataRow extends StatelessWidget {
  final AdjuntoItem adjunto;
  const _MetadataRow({required this.adjunto});

  @override
  Widget build(BuildContext context) {
    final theme     = FluentTheme.of(context);
    final dateLabel = DateFormat('dd/MM/yyyy HH:mm')
        .format(adjunto.createdAt.toLocal());

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorTransparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: Column(
        children: [
          _MetaItem(label: 'Tipo',    value: adjunto.entidadTipo),
          _MetaItem(label: 'Formato', value: adjunto.extension),
          _MetaItem(label: 'Tamaño',  value: adjunto.tamanioLabel),
          _MetaItem(label: 'Fecha',   value: dateLabel),
          if (adjunto.subidoPor != null)
            _MetaItem(label: 'Subido por', value: adjunto.subidoPor!),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final String label;
  final String value;
  const _MetaItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.typography.caption),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vista previa — contenedor principal (imagen o PDF)
// ---------------------------------------------------------------------------

class _PreviaDialog extends StatelessWidget {
  final AdjuntoItem adjunto;
  final String      url;

  const _PreviaDialog({required this.adjunto, required this.url});

  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.of(context).size;
    final theme = FluentTheme.of(context);
    final w     = (size.width  * 0.92).clamp(420.0, 1100.0);
    final h     = (size.height * 0.88).clamp(360.0,  820.0);

    return Center(
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // ---- Header ----
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(
                  bottom: BorderSide(
                    color: theme.resources.cardStrokeColorDefault,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _FileIcon(
                    category: adjunto.iconCategory,
                    ext: adjunto.extension,
                  ),
                  const SizedBox(width: 12),
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
                        Text(
                          '${adjunto.tamanioLabel} · ${adjunto.extension}',
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Cerrar',
                    child: IconButton(
                      icon: const Icon(FluentIcons.cancel, size: 14),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),

            // ---- Contenido ----
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(8)),
                child: adjunto.iconCategory == 'image'
                    ? _ImagePreview(url: url)
                    : _PdfPreview(url: url),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vista previa de imagen
// ---------------------------------------------------------------------------

class _ImagePreview extends StatelessWidget {
  final String url;
  const _ImagePreview({required this.url});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 6.0,
        child: Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              final total = progress.expectedTotalBytes;
              final done  = progress.cumulativeBytesLoaded;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProgressRing(
                      value: total != null ? done / total * 100 : null,
                    ),
                    if (total != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${(done / total * 100).toStringAsFixed(0)} %',
                        style: FluentTheme.of(ctx).typography.caption?.copyWith(
                              color: Colors.white,
                            ),
                      ),
                    ],
                  ],
                ),
              );
            },
            errorBuilder: (ctx, _, __) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.error_badge, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'No se pudo cargar la imagen',
                    style: FluentTheme.of(ctx)
                        .typography
                        .body
                        ?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vista previa de PDF
// ---------------------------------------------------------------------------

class _PdfPreview extends StatefulWidget {
  final String url;
  const _PdfPreview({required this.url});

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  late final PdfViewerController _ctrl;
  bool    _loading     = true;
  String? _error;
  int     _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _ctrl = PdfViewerController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Stack(
      children: [
        SfPdfViewer.network(
          widget.url,
          controller: _ctrl,
          onDocumentLoaded: (_) {
            setState(() => _loading = false);
          },
          onDocumentLoadFailed: (details) {
            setState(() {
              _loading = false;
              _error   = details.error;
            });
          },
          onPageChanged: (details) {
            setState(() => _currentPage = details.newPageNumber);
          },
        ),

        // Loading overlay
        if (_loading)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProgressRing(),
                SizedBox(height: 12),
                Text('Cargando PDF…'),
              ],
            ),
          ),

        // Error overlay
        if (_error != null)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.error_badge, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  'Error al cargar el PDF',
                  style: theme.typography.body,
                ),
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ),

        // Indicador de página (esquina inferior derecha)
        if (!_loading && _error == null)
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Pág. $_currentPage / ${_ctrl.pageCount}',
                style: theme.typography.caption
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
