import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/com_mensaje.dart';

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
  // Suscripción Realtime para esta conversación específica.
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
        // Reconexión iOS/Android → re-fetch para no perder mensajes del background.
        if (status == RealtimeSubscribeStatus.subscribed) {
          ref.invalidateSelf();
        }
      });

  ref.onDispose(() {
    channel.unsubscribe();
  });

  final rows = await Supabase.instance.client.rpc(
    'com_get_mensajes_conversacion',
    params: {'p_conv_id': convId, 'p_limit': 100, 'p_offset': 0},
  ) as List;

  return rows
      .map((r) => ComMensaje.fromJson(r as Map<String, dynamic>))
      .toList();
});
