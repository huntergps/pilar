import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

import 'package:brick_gen/brick_gen.dart';

import '../../../core/providers/empresa_provider.dart';

// ---------------------------------------------------------------------------
// mensajesProvider — mensajes de una conversación
// ---------------------------------------------------------------------------

/// Carga los mensajes de la conversación [convId] via RPC y se suscribe a
/// cambios en Realtime para actualizar en tiempo real.
///
/// Firma confirmada en DB:
/// `com_get_mensajes_conversacion(p_conv_id UUID, p_limit INT, p_offset INT)
///  RETURNS SETOF com_mensajes`
final mensajesProvider = FutureProvider.autoDispose
    .family<List<ComMensaje>, String>((ref, convId) async {
  // Flag para distinguir suscripción inicial de reconexión.
  // El callback 'subscribed' se dispara en AMBOS casos; solo en reconexión
  // hay que re-fetch (la suscripción inicial ya ejecuta el rpc() abajo).
  var suscripcionInicial = true;

  // Suscripción Realtime para esta conversación específica.
  // NOTA: REPLICA IDENTITY FULL en com_mensajes permite que el servidor
  // Realtime evalúe el filtro conversacion_id en UPDATE/DELETE además de INSERT.
  final channel = Supabase.instance.client
      .channel('com_msgs_$convId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'com_mensajes',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversacion_id',
          value: convId,
        ),
        callback: (_) => ref.invalidateSelf(),
      )
      .subscribe((status, [_]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (suscripcionInicial) {
            // Primera suscripción: la carga inicial la hace el rpc() abajo.
            suscripcionInicial = false;
          } else {
            // Reconexión (ej. iOS resume): re-fetch para no perder mensajes.
            ref.invalidateSelf();
          }
        }
      });

  ref.onDispose(() {
    channel.unsubscribe();
  });

  // Ruta nativa (SQLite) en plataformas non-web.
  if (!kIsWeb && PilarRepository.isInitialized) {
    final repo = PilarRepository.instance;
    final results = await repo.get<ComMensaje>(
      query: Query(where: [Where.exact('conversacionId', convId)]),
      policy: OfflineFirstGetPolicy.localOnly,
    );
    // Si hay datos locales los devolvemos; luego Realtime actualizará.
    if (results.isNotEmpty) return results;
    // Sin caché local: fetch remoto y almacenar en SQLite.
    return repo.get<ComMensaje>(
      query: Query(where: [Where.exact('conversacionId', convId)]),
      policy: OfflineFirstGetPolicy.awaitRemote,
    );
  }

  // Web fallback: RPC directa.
  final rows = await Supabase.instance.client.rpc(
    'com_get_mensajes_conversacion',
    params: {'p_conv_id': convId, 'p_limit': 100, 'p_offset': 0},
  ) as List;

  return rows
      .map((r) => ComMensaje.fromJson(r as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// historialMensajesProvider — mensajes outbound de la empresa (para HistorialTab)
// ---------------------------------------------------------------------------

/// Carga los últimos 200 mensajes salientes de la empresa activa.
/// Movido desde historial_tab.dart para cumplir la convención de no tener
/// providers con acceso directo a Supabase dentro de los screens.
final historialMensajesProvider =
    FutureProvider.autoDispose<List<ComMensaje>>((ref) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return const [];

  // Ruta nativa (SQLite) en plataformas non-web.
  if (!kIsWeb && PilarRepository.isInitialized) {
    final repo = PilarRepository.instance;
    final results = await repo.get<ComMensaje>(
      query: Query(
        where: [Where.exact('tipo', 'outbound')],
        orderBy: [const OrderBy('creadoEn', ascending: false)],
        limit: 200,
      ),
      policy: OfflineFirstGetPolicy.awaitRemote,
    );
    return results;
  }

  // Web fallback: SELECT directo.
  final rows = await Supabase.instance.client
      .from('com_mensajes')
      .select()
      .eq('empresa_id', empresaId)
      .eq('tipo', 'outbound')
      .order('creado_en', ascending: false)
      .limit(200) as List;

  return rows
      .map((r) => ComMensaje.fromJson(r as Map<String, dynamic>))
      .toList();
});
