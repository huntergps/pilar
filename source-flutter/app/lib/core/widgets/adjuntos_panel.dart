// AdjuntosPanel — widget reutilizable para mostrar y subir adjuntos.
//
// Uso: incrustar en cualquier pantalla de detalle de entidad.
//
//   AdjuntosPanel(
//     empresaId: empresaId,
//     entidadTipo: 'factura',
//     entidadId: facturaId,
//   )
//
// El panel:
//   · Lista los adjuntos activos con icono, nombre, tamaño, fecha
//   · Botón "Adjuntar archivo" → FilePicker → TUS upload → registrar_adjunto
//   · Barra de progreso animada durante el upload
//   · Opción de eliminar (con confirmación) y renombrar
//   · Tap en un adjunto → genera URL firmada y abre en el browser/app

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

import '../models/adjunto_model.dart';
import '../providers/adjuntos_provider.dart';
import '../services/upload_service.dart';

// ---------------------------------------------------------------------------
// Panel principal
// ---------------------------------------------------------------------------

class AdjuntosPanel extends ConsumerStatefulWidget {
  final String empresaId;
  final String entidadTipo;
  final String entidadId;

  /// Extensiones permitidas para el picker. Null = cualquier tipo.
  final List<String>? allowedExtensions;

  /// Título del panel. Por defecto "Adjuntos".
  final String? titulo;

  /// Tags que se aplican automáticamente al subir un archivo.
  /// Útil para que cada módulo pre-etiquete sus adjuntos.
  /// Ejemplo: `['factura', '2026-01']`
  final List<String> defaultTags;

  const AdjuntosPanel({
    super.key,
    required this.empresaId,
    required this.entidadTipo,
    required this.entidadId,
    this.allowedExtensions,
    this.titulo,
    this.defaultTags = const [],
  });

  @override
  ConsumerState<AdjuntosPanel> createState() => _AdjuntosPanelState();
}

class _AdjuntosPanelState extends ConsumerState<AdjuntosPanel> {
  UploadCancelToken? _cancelToken;

  (String, String) get _key => (widget.entidadTipo, widget.entidadId);

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final adjuntosAsync = ref.watch(adjuntosNotifierProvider(_key));

    return adjuntosAsync.when(
      loading: () => const Center(child: ProgressRing()),
      error: (e, _) => _ErrorView(message: e.toString()),
      data: (adjState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado
          _PanelHeader(
            titulo: widget.titulo ?? 'Adjuntos',
            count: adjState.items.length,
            onUpload: adjState.isUploading
                ? null
                : () => _startUpload(context),
          ),

          const SizedBox(height: 8),

          // Barra de progreso (visible durante upload)
          if (adjState.isUploading) ...[
            _UploadProgressBar(
              progress: adjState.uploadProgress,
              onCancel: () => _cancelToken?.cancel(),
            ),
            const SizedBox(height: 8),
          ],

          // Error (si existe)
          if (adjState.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoBar(
                title: Text('Error al subir: ${adjState.error}'),
                severity: InfoBarSeverity.error,
                isLong: true,
              ),
            ),

          // Lista de adjuntos
          if (adjState.items.isEmpty && !adjState.isUploading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Sin adjuntos',
                  style: theme.typography.body?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ),
            )
          else
            ...adjState.items.map(
              (adjunto) => _AdjuntoTile(
                adjunto: adjunto,
                onEliminar: () => _confirmarEliminar(context, adjunto),
                onRenombrar: () => _mostrarRenombrar(context, adjunto),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _startUpload(BuildContext context) async {
    _cancelToken = UploadCancelToken();

    await ref.read(adjuntosNotifierProvider(_key).notifier).upload(
          empresaId: widget.empresaId,
          allowedExtensions: widget.allowedExtensions,
          defaultTags: widget.defaultTags,
          cancelToken: _cancelToken,
        );

    _cancelToken = null;
  }

  Future<void> _confirmarEliminar(BuildContext ctx, AdjuntoItem adjunto) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => ContentDialog(
        title: const Text('Eliminar adjunto'),
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

    if (confirmed == true) {
      await ref
          .read(adjuntosNotifierProvider(_key).notifier)
          .eliminar(adjunto.id);
    }
  }

  Future<void> _mostrarRenombrar(BuildContext ctx, AdjuntoItem adjunto) async {
    final ctrl = TextEditingController(text: adjunto.nombre);
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => ContentDialog(
        title: const Text('Renombrar adjunto'),
        content: TextBox(
          controller: ctrl,
          placeholder: 'Nombre del archivo',
          autofocus: true,
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            child: const Text('Guardar'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      await ref
          .read(adjuntosNotifierProvider(_key).notifier)
          .renombrar(adjunto.id, ctrl.text.trim());
    }

    ctrl.dispose();
  }
}

// ---------------------------------------------------------------------------
// Encabezado del panel
// ---------------------------------------------------------------------------

class _PanelHeader extends StatelessWidget {
  final String titulo;
  final int count;
  final VoidCallback? onUpload;

  const _PanelHeader({
    required this.titulo,
    required this.count,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Text(
          titulo,
          style: theme.typography.bodyStrong,
        ),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: theme.typography.caption?.copyWith(
                color: theme.accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const Spacer(),
        Button(
          onPressed: onUpload,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.attach, size: 14),
              SizedBox(width: 6),
              Text('Adjuntar'),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de progreso de upload
// ---------------------------------------------------------------------------

class _UploadProgressBar extends StatelessWidget {
  final UploadProgress? progress;
  final VoidCallback? onCancel;

  const _UploadProgressBar({required this.progress, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final p = progress;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
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
// Tile de un adjunto
// ---------------------------------------------------------------------------

class _AdjuntoTile extends StatelessWidget {
  final AdjuntoItem adjunto;
  final VoidCallback onEliminar;
  final VoidCallback onRenombrar;

  const _AdjuntoTile({
    required this.adjunto,
    required this.onEliminar,
    required this.onRenombrar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dateLabel =
        DateFormat('dd/MM/yyyy HH:mm').format(adjunto.createdAt.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile.selectable(
        leading: _FileIcon(category: adjunto.iconCategory, ext: adjunto.extension),
        title: Text(adjunto.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${adjunto.tamanioLabel} · $dateLabel',
          style: theme.typography.caption?.copyWith(
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Abrir',
              child: IconButton(
                icon: const Icon(FluentIcons.open_in_new_window, size: 14),
                onPressed: () => _open(),
              ),
            ),
            Tooltip(
              message: 'Renombrar',
              child: IconButton(
                icon: const Icon(FluentIcons.rename, size: 14),
                onPressed: onRenombrar,
              ),
            ),
            Tooltip(
              message: 'Eliminar',
              child: IconButton(
                icon: Icon(
                  FluentIcons.delete,
                  size: 14,
                  color: Colors.red,
                ),
                onPressed: onEliminar,
              ),
            ),
          ],
        ),
        onPressed: () => _open(),
      ),
    );
  }

  Future<void> _open() async {
    final url = await UploadService.createSignedUrl(adjunto.storagePath);
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}

// ---------------------------------------------------------------------------
// Ícono por tipo de archivo
// ---------------------------------------------------------------------------

class _FileIcon extends StatelessWidget {
  final String category;
  final String ext;

  const _FileIcon({required this.category, required this.ext});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = _colorForCategory(category, theme);

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

  Color _colorForCategory(String cat, FluentThemeData theme) {
    switch (cat) {
      case 'image': return Colors.green;
      case 'pdf':   return Colors.red;
      case 'word':  return Colors.blue;
      case 'excel': return const Color(0xFF217346); // Excel green
      case 'ppt':   return Colors.orange;
      case 'csv':   return Colors.teal;
      case 'zip':   return Colors.purple;
      default:      return theme.accentColor;
    }
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) => InfoBar(
        title: Text('Error al cargar adjuntos: $message'),
        severity: InfoBarSeverity.error,
      );
}
