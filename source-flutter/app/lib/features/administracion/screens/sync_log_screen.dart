import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pilar_breakpoints.dart';
import '../../../core/theme/pilar_spacing.dart';
import '../../../core/widgets/loading_spinner.dart';
import '../../../core/widgets/empty_state.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Reads all pending items from Brick's offline HTTP queue.
///
/// Returns an empty list on web (no SQLite available) and when the repository
/// is not yet initialized.
/// Auto-refresca cada 5 s mientras alguien lo esté observando
/// (p.ej. el badge en PilarHeader), garantizando que el conteo pendiente
/// se actualice aunque SyncLogScreen no esté abierta.
final syncQueueItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (kIsWeb) return const [];
  if (!PilarRepository.isInitialized) return const [];

  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  return PilarRepository.instance.getOfflineQueueItems();
});

/// Fuerza un reintento inmediato de todos los requests pendientes en la cola
/// offline de Brick.
///
/// No-op en web (sin SQLite) o cuando el repositorio no está inicializado.
/// [RestOfflineRequestQueue.start] es síncrono — lanza el procesamiento en
/// background y retorna enseguida. Después invalidamos [syncQueueItemsProvider]
/// para que la UI refresque la lista tras un breve delay.
final syncRetryProvider = FutureProvider.autoDispose<void>((ref) async {
  if (kIsWeb) return;
  if (!PilarRepository.isInitialized) return;
  PilarRepository.instance.retryOfflineQueue();
  // Pequeño delay para dar tiempo a que Brick procese al menos el primer item
  // antes de refrescar la vista.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  ref.invalidate(syncQueueItemsProvider);
});

// ---------------------------------------------------------------------------
// SyncLogScreen
// ---------------------------------------------------------------------------

/// Pantalla de administración que muestra la cola de sincronización offline.
///
/// Permite visualizar los requests HTTP pendientes que Brick reintentará
/// una vez se restablezca la conexión a Supabase, así como eliminar
/// entradas individuales o la cola completa.
class SyncLogScreen extends ConsumerStatefulWidget {
  const SyncLogScreen({super.key});

  @override
  ConsumerState<SyncLogScreen> createState() => _SyncLogScreenState();
}

class _SyncLogScreenState extends ConsumerState<SyncLogScreen> {
  Timer? _autoRefresh;

  /// true mientras [syncRetryProvider] está ejecutándose.
  bool _retrying = false;

  /// Mensaje de error del último reintento fallido; null si no hay error.
  String? _retryError;

  @override
  void initState() {
    super.initState();
    // Auto-refresh cada 10 segundos para mostrar cambios en tiempo real.
    _autoRefresh = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(syncQueueItemsProvider);
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _clearAll(
      BuildContext ctx, List<Map<String, dynamic>> items) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => ContentDialog(
        title: const Text('Vaciar cola de sincronización'),
        content: Text(
            'Se eliminarán ${items.length} ${items.length == 1 ? 'item' : 'items'} '
            'pendientes. Esta acción no se puede deshacer.'),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Vaciar cola'),
          ),
        ],
      ),
    );
    if (ok != true || !ctx.mounted) return;
    if (!PilarRepository.isInitialized) return;

    for (final item in items) {
      final id = item['id'] as int?;
      if (id != null) {
        await PilarRepository.instance.deleteOfflineQueueItem(id);
      }
    }
    ref.invalidate(syncQueueItemsProvider);
  }

  Future<void> _deleteItem(BuildContext ctx, int id) async {
    if (!PilarRepository.isInitialized) return;
    await PilarRepository.instance.deleteOfflineQueueItem(id);
    ref.invalidate(syncQueueItemsProvider);
  }

  Future<void> _retryNow() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _retryError = null; // limpiar error anterior
    });
    try {
      // Invalidate to trigger the provider — it re-runs retryOfflineQueue()
      // and then invalidates syncQueueItemsProvider when done.
      ref.invalidate(syncRetryProvider);
      // Wait for the provider to settle so we can flip the loading flag.
      await ref.read(syncRetryProvider.future);
      // Éxito: la lista se actualiza sola vía syncQueueItemsProvider.
    } catch (e) {
      if (mounted) {
        setState(() => _retryError = _retryErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  String _retryErrorMessage(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('timeout')) {
      return 'Sin conexión a internet. Vuelve a intentarlo cuando recuperes la red.';
    }
    return 'Error al reintentar: ${e.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const _WebUnavailable();
    }

    final itemsAsync = ref.watch(syncQueueItemsProvider);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Cola de Sincronización'),
        commandBar: itemsAsync.when(
          data: (items) => CommandBar(
            primaryItems: [
              CommandBarButton(
                icon: const Icon(FluentIcons.refresh),
                label: const Text('Actualizar'),
                onPressed: () => ref.invalidate(syncQueueItemsProvider),
              ),
              if (items.isNotEmpty) ...[
                CommandBarButton(
                  icon: _retrying
                      ? const PilarProgressRing(size: 14)
                      : const Icon(FluentIcons.sync),
                  label: const Text('Reintentar ahora'),
                  onPressed: _retrying ? null : _retryNow,
                ),
                CommandBarButton(
                  icon: const Icon(FluentIcons.delete),
                  label: const Text('Vaciar cola'),
                  onPressed: () => _clearAll(context, items),
                ),
              ],
            ],
          ),
          loading: () => const CommandBar(primaryItems: []),
          error: (_, __) => const CommandBar(primaryItems: []),
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_retryError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.sm, Spacing.md, 0),
              child: InfoBar(
                title: const Text('Error al reintentar sincronización'),
                content: Text(_retryError!),
                severity: InfoBarSeverity.error,
                isIconVisible: true,
                onClose: () => setState(() => _retryError = null),
              ),
            ),
          Expanded(
            child: itemsAsync.when(
              loading: () => const PilarLoadingCenter(),
              error: (e, _) => Center(
                child: InfoBar(
                  title: const Text('Error al leer la cola'),
                  content: Text(e.toString()),
                  severity: InfoBarSeverity.error,
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return PilarEmptyState(
                    icon: FluentIcons.sync_status,
                    iconColor: Colors.successPrimaryColor,
                    message: 'Cola vacía — todo sincronizado',
                    subtitle: 'No hay requests pendientes de envío a Supabase.',
                    action: Button(
                      onPressed: () => ref.invalidate(syncQueueItemsProvider),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.refresh, size: 14),
                          SizedBox(width: Spacing.sm),
                          Text('Actualizar'),
                        ],
                      ),
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (ctx, constraints) {
                    if (constraints.maxWidth >= PilarBreakpoints.tablet) {
                      return _DataGridView(
                        items: items,
                        onDelete: (id) => _deleteItem(ctx, id),
                      );
                    }
                    return _ListViewBody(
                      items: items,
                      onDelete: (id) => _deleteItem(ctx, id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Extrae el nombre de la tabla o endpoint de la URL REST de Supabase.
///
/// `/rest/v1/tabla?colums=...` → `tabla`
/// `https://xxx.supabase.co/rest/v1/tabla` → `tabla`
String _parseEntityName(String? urlStr) {
  if (urlStr == null) return '—';
  final uri = Uri.tryParse(urlStr);
  if (uri == null) return '—';
  final segments = uri.pathSegments;
  final restIdx = segments.indexOf('v1');
  if (restIdx >= 0 && restIdx + 1 < segments.length) {
    return segments[restIdx + 1];
  }
  return segments.lastOrNull ?? '—';
}

String _formatTs(dynamic ms) {
  if (ms == null) return '—';
  final ts = int.tryParse(ms.toString());
  if (ts == null || ts == 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

String _methodBadgeColor(String? method) {
  return method?.toUpperCase() ?? 'HTTP';
}

// ---------------------------------------------------------------------------
// SfDataGrid view (≥ PilarBreakpoints.tablet)
// ---------------------------------------------------------------------------

class _DataGridView extends StatelessWidget {
  const _DataGridView({required this.items, required this.onDelete});

  final List<Map<String, dynamic>> items;
  final void Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        // Encabezado de tabla
        Container(
          color: theme.accentColor.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.ms, vertical: Spacing.sm),
          child: Row(
            children: [
              SizedBox(
                  width: 60,
                  child: Text('#',
                      style: theme.typography.bodyStrong)),
              SizedBox(
                  width: 80,
                  child: Text('Método',
                      style: theme.typography.bodyStrong)),
              Expanded(
                  flex: 2,
                  child: Text('Entidad',
                      style: theme.typography.bodyStrong)),
              Expanded(
                  flex: 3,
                  child: Text('URL',
                      style: theme.typography.bodyStrong)),
              SizedBox(
                  width: 120,
                  child: Text('Creado',
                      style: theme.typography.bodyStrong)),
              SizedBox(
                  width: 70,
                  child: Text('Intentos',
                      style: theme.typography.bodyStrong)),
              const SizedBox(width: Spacing.xl),
            ],
          ),
        ),
        ...items.asMap().entries.map((e) {
          final i = e.key;
          final row = e.value;
          final id = row['id'] as int? ?? 0;
          return _TableRow(
            index: i,
            row: row,
            id: id,
            onDelete: onDelete,
          );
        }),
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.index,
    required this.row,
    required this.id,
    required this.onDelete,
  });

  final int index;
  final Map<String, dynamic> row;
  final int id;
  final void Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = index.isEven
        ? Colors.transparent
        : (isDark
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFF8F8F8));
    final method = row['request_method'] as String? ?? '?';
    final url = row['url'] as String? ?? '';
    final entity = _parseEntityName(url);
    final createdAt = _formatTs(row['created_at']);
    final attempts = row['attempts']?.toString() ?? '1';
    final locked = (row['locked'] as int? ?? 0) == 1;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.ms, vertical: Spacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '#$id',
              style:
                  theme.typography.caption?.copyWith(color: theme.resources.textFillColorSecondary),
            ),
          ),
          SizedBox(
            width: 80,
            child: _MethodBadge(method: method),
          ),
          Expanded(
            flex: 2,
            child: Text(
              entity,
              style: theme.typography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Tooltip(
              message: url,
              child: Text(
                url,
                style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(createdAt, style: theme.typography.body),
          ),
          SizedBox(
            width: 70,
            child: Row(
              children: [
                Text(attempts, style: theme.typography.body),
                if (locked) ...[
                  const SizedBox(width: Spacing.xs),
                  Icon(FluentIcons.lock, size: 12,
                      color: theme.accentColor),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(FluentIcons.delete, size: 14,
                  color: Colors.errorPrimaryColor),
              onPressed: () => onDelete(id),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ListView view (< PilarBreakpoints.tablet)
// ---------------------------------------------------------------------------

class _ListViewBody extends StatelessWidget {
  const _ListViewBody({required this.items, required this.onDelete});

  final List<Map<String, dynamic>> items;
  final void Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.ms),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
      itemBuilder: (ctx, i) {
        final row = items[i];
        final id = row['id'] as int? ?? 0;
        final method = row['request_method'] as String? ?? '?';
        final url = row['url'] as String? ?? '';
        final entity = _parseEntityName(url);
        final createdAt = _formatTs(row['created_at']);
        final attempts = row['attempts']?.toString() ?? '1';

        final theme = FluentTheme.of(ctx);
        return Card(
          padding: const EdgeInsets.all(Spacing.ms),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _MethodBadge(method: method),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(entity,
                        style: theme.typography.bodyStrong,
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.delete,
                        size: 14, color: Colors.errorPrimaryColor),
                    onPressed: () => onDelete(id),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                url,
                style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Icon(FluentIcons.clock, size: 12,
                      color: theme.resources.textFillColorSecondary),
                  const SizedBox(width: Spacing.xs),
                  Text(createdAt, style: theme.typography.caption),
                  const SizedBox(width: Spacing.ms),
                  Icon(FluentIcons.refresh, size: 12,
                      color: theme.resources.textFillColorSecondary),
                  const SizedBox(width: Spacing.xs),
                  Text('$attempts intentos',
                      style: theme.typography.caption),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method});
  final String method;

  @override
  Widget build(BuildContext context) {
    final color = switch (method.toUpperCase()) {
      'POST' => const Color(0xFF16A34A),
      'PATCH' || 'PUT' => const Color(0xFFD97706),
      'DELETE' => const Color(0xFFDC2626),
      _ => const Color(0xFF6B7280),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        _methodBadgeColor(method),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}


class _WebUnavailable extends StatelessWidget {
  const _WebUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: InfoBar(
        title: Text('No disponible en web'),
        content: Text(
            'La cola de sincronización offline solo está disponible en aplicaciones nativas.'),
        severity: InfoBarSeverity.info,
      ),
    );
  }
}
