import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/empresa_provider.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Notificacion individual de la bandeja del usuario.
class NotificacionItem {
  const NotificacionItem({
    required this.id,
    required this.tipo,
    required this.titulo,
    this.mensaje,
    required this.leida,
    required this.creadaEn,
  });

  final String id;

  /// Categoria de la notificacion, p.ej. "sri", "venta", "sistema".
  final String tipo;

  final String titulo;
  final String? mensaje;
  final bool leida;
  final DateTime creadaEn;

  factory NotificacionItem.fromJson(Map<String, dynamic> json) {
    return NotificacionItem(
      id: json['id'] as String,
      tipo: json['tipo'] as String? ?? 'sistema',
      titulo: json['titulo'] as String,
      mensaje: json['mensaje'] as String?,
      leida: json['leida'] as bool? ?? false,
      creadaEn: DateTime.parse(json['creada_en'] as String),
    );
  }
}

// ---------------------------------------------------------------------------
// Badge provider (conteo de no leidas)
// ---------------------------------------------------------------------------

/// Numero de notificaciones no leidas del usuario.
///
/// Estrategia hibrida:
/// 1. Fetch inicial via RPC al suscribirse.
/// 2. Subscription de Supabase Realtime para INSERT en `notificaciones_usuario`
///    — en cada evento INSERT se refetch el conteo real para evitar
///    double-counting en caso de mensajes duplicados.
/// 3. Refresh periodico cada 30 s como fallback cuando el canal Realtime
///    no esta disponible (ej. conexion inestable).
///
/// Nota: el canal se cancela automaticamente al disposar el provider (ref.onDispose).
final notificacionesBadgeProvider = StreamProvider<int>((ref) async* {
  ref.watch(authStateProvider);
  final empresaId = ref.watch(empresaActivaIdProvider);

  if (empresaId == null) {
    yield 0;
    return;
  }

  final client = ref.watch(supabaseClientProvider);

  // ---- Controlador que alimenta el stream de conteos ----
  final controller = StreamController<int>();

  // Funcion reutilizable para obtener el conteo actual.
  Future<void> fetchCount() async {
    try {
      final result =
          await client.rpc('get_count_notificaciones_no_leidas');
      if (!controller.isClosed) {
        controller.add((result as int?) ?? 0);
      }
    } catch (_) {
      // En caso de error de red no se emite nada; el valor anterior persiste.
    }
  }

  // ---- Fetch inicial ----
  await fetchCount();

  // ---- Realtime: INSERT en notificaciones_usuario ----
  final channel = client
      .channel('notificaciones_badge_$empresaId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notificaciones_usuario',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'empresa_id',
          value: empresaId,
        ),
        callback: (_) => fetchCount(),
      )
      .subscribe();

  // ---- Refresh periodico cada 30 s como fallback ----
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (!controller.isClosed) fetchCount();
  });

  // ---- Limpieza al disponer el provider ----
  ref.onDispose(() {
    timer.cancel();
    channel.unsubscribe();
    controller.close();
  });

  yield* controller.stream;
});

// ---------------------------------------------------------------------------
// Lista de notificaciones
// ---------------------------------------------------------------------------

/// Ultimas 20 notificaciones del usuario (leidas y no leidas).
///
/// Invalide este provider manualmente tras marcar una notificacion como leida:
/// ```dart
/// ref.invalidate(notificacionesProvider);
/// ```
final notificacionesProvider =
    FutureProvider<List<NotificacionItem>>((ref) async {
  ref.watch(authStateProvider);

  final client = ref.watch(supabaseClientProvider);
  final data = await client.rpc(
    'get_notificaciones',
    params: {'p_limit': 20, 'p_offset': 0},
  );
  return (data as List)
      .map((e) => NotificacionItem.fromJson(e as Map<String, dynamic>))
      .toList();
});
