import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/alertas_provider.dart';

/// Panel de alertas activas de la empresa.
///
/// Se abre desde el icono de alerta en [PilarHeader].
/// Muestra las alertas ordenadas por severidad (critical → info).
/// Permite resolver (con nota opcional) o ignorar cada alerta.
class AlertasPanel extends ConsumerWidget {
  const AlertasPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertasAsync = ref.watch(alertasActivasProvider);

    return ContentDialog(
      title: const Text('Alertas del sistema'),
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
      content: PilarAsyncBuilder<List<AlertaItem>>(
        value: alertasAsync,
        isEmpty: (list) => list.isEmpty,
        emptyWidget: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.shield_alert, size: 40),
                SizedBox(height: 12),
                Text('No hay alertas activas'),
              ],
            ),
          ),
        ),
        builder: (context, alertas) => ListView.separated(
          shrinkWrap: true,
          itemCount: alertas.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, i) => _AlertaTile(
            alerta: alertas[i],
            onResolved: () {
              ref.invalidate(alertasActivasProvider);
              ref.invalidate(alertasCountProvider);
            },
          ),
        ),
      ),
      actions: [
        Button(
          child: const Text('Cerrar'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de alerta individual
// ---------------------------------------------------------------------------

class _AlertaTile extends ConsumerStatefulWidget {
  final AlertaItem alerta;
  final VoidCallback onResolved;

  const _AlertaTile({required this.alerta, required this.onResolved});

  @override
  ConsumerState<_AlertaTile> createState() => _AlertaTileState();
}

class _AlertaTileState extends ConsumerState<_AlertaTile> {
  bool _loading = false;

  Future<void> _resolver() async {
    // Pedir nota opcional
    final nota = await _showNotaDialog();
    if (nota == null) return; // cancelado

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.rpc(
        'resolver_alerta',
        params: {
          'p_alerta_id': widget.alerta.id,
          if (nota.isNotEmpty) 'p_nota': nota,
        },
      );
      widget.onResolved();
    } catch (e) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (_, close) => InfoBar(
            title: const Text('Error al resolver alerta'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ignorar() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.rpc(
        'ignorar_alerta',
        params: {'p_alerta_id': widget.alerta.id},
      );
      widget.onResolved();
    } catch (e) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (_, close) => InfoBar(
            title: const Text('Error al ignorar alerta'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _showNotaDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('Resolver alerta'),
        content: InfoLabel(
          label: 'Nota de resolución (opcional)',
          child: TextBox(
            controller: ctrl,
            placeholder: 'Ej: Certificado renovado, problema solucionado…',
            maxLines: 3,
          ),
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: const Text('Resolver'),
            onPressed: () => Navigator.pop(context, ctrl.text),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final alerta = widget.alerta;
    final color = _severityColor(alerta.severidad, theme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icono de severidad
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 12),
            child: Icon(
              _severityIcon(alerta.severidad),
              size: 18,
              color: color,
            ),
          ),

          // Contenido
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        alerta.titulo,
                        style: theme.typography.bodyStrong,
                      ),
                    ),
                    // Badge de severidad
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _severityLabel(alerta.severidad),
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (alerta.cuerpo != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    alerta.cuerpo!,
                    style: theme.typography.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${alerta.origenModulo} · '
                      '${DateFormat('dd/MM/yyyy HH:mm').format(alerta.creadaAt.toLocal())}',
                      style: theme.typography.caption
                          ?.copyWith(color: theme.inactiveColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Acciones
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  )
                else
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _resolver,
                        child: const Text('Resolver'),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: _ignorar,
                        child: const Text('Ignorar'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers de severidad
// ---------------------------------------------------------------------------

Color _severityColor(String severidad, FluentThemeData theme) {
  return switch (severidad) {
    'critical' => Colors.errorPrimaryColor,
    'error'    => Colors.errorPrimaryColor,
    'warning'  => const Color(0xFFF59E0B),
    _          => theme.accentColor,
  };
}

IconData _severityIcon(String severidad) {
  return switch (severidad) {
    'critical' => FluentIcons.error_badge,
    'error'    => FluentIcons.status_circle_error_x,
    'warning'  => FluentIcons.shield_alert,
    _          => FluentIcons.info_solid,
  };
}

String _severityLabel(String severidad) {
  return switch (severidad) {
    'critical' => 'Crítico',
    'error'    => 'Error',
    'warning'  => 'Advertencia',
    _          => 'Info',
  };
}
