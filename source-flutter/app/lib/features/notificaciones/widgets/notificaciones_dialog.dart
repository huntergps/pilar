import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/notificaciones_provider.dart';

/// Dialog que muestra las últimas 20 notificaciones del usuario.
///
/// Usa [PilarAsyncBuilder] para los tres estados (loading / error / data).
/// Incluye una acción para marcar todas las notificaciones como leídas
/// vía el RPC `marcar_todas_notificaciones_leidas`, e invalida los
/// providers [notificacionesProvider] y [notificacionesBadgeProvider]
/// para que el badge de la shell se actualice inmediatamente.
///
/// Uso típico desde la shell:
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (_) => const NotificacionesDialog(),
/// );
/// ```
class NotificacionesDialog extends ConsumerWidget {
  const NotificacionesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificacionesAsync = ref.watch(notificacionesProvider);

    return ContentDialog(
      title: const Text('Notificaciones'),
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
      content: PilarAsyncBuilder<List<NotificacionItem>>(
        value: notificacionesAsync,
        isEmpty: (list) => list.isEmpty,
        emptyWidget: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('Sin notificaciones'),
          ),
        ),
        builder: (context, items) => ListView.separated(
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, i) {
            final n = items[i];
            return _NotificacionTile(notificacion: n);
          },
        ),
      ),
      actions: [
        Button(
          child: const Text('Cerrar'),
          onPressed: () => Navigator.pop(context),
        ),
        HyperlinkButton(
          child: const Text('Marcar todas como leídas'),
          onPressed: () async {
            await Supabase.instance.client
                .rpc('marcar_todas_notificaciones_leidas');

            ref.invalidate(notificacionesProvider);
            ref.invalidate(notificacionesBadgeProvider);

            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de notificación individual
// ---------------------------------------------------------------------------

class _NotificacionTile extends StatelessWidget {
  final NotificacionItem notificacion;

  const _NotificacionTile({required this.notificacion});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(
              notificacion.leida
                  ? FluentIcons.ringer
                  : FluentIcons.ringer_solid,
              size: 16,
              color: notificacion.leida
                  ? theme.inactiveColor
                  : theme.accentColor,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notificacion.titulo,
                  style: notificacion.leida
                      ? theme.typography.body
                      : theme.typography.bodyStrong,
                ),
                if (notificacion.mensaje != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    notificacion.mensaje!,
                    style: theme.typography.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
