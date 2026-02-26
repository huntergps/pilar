import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/repository_provider.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Notificacion individual de la bandeja del usuario.
class NotificacionItem {
  const NotificacionItem({
    required this.id,
    required this.tipo,
    required this.titulo,
    this.cuerpo,
    required this.leida,
    required this.creadaAt,
    this.icono,
    this.accionUrl,
  });

  final String id;

  /// Categoria de la notificacion, p.ej. "sri", "venta", "sistema".
  final String tipo;

  final String titulo;
  final String? cuerpo;
  final bool leida;
  final DateTime creadaAt;

  /// Nombre del icono sugerido por el backend (opcional).
  final String? icono;

  /// URL de acción asociada — deep-link para navegación directa (opcional).
  final String? accionUrl;

  factory NotificacionItem.fromJson(Map<String, dynamic> json) {
    return NotificacionItem(
      id: json['id'] as String,
      tipo: json['tipo'] as String? ?? 'sistema',
      titulo: json['titulo'] as String,
      cuerpo: json['cuerpo'] as String?,
      leida: json['leida'] as bool? ?? false,
      creadaAt: DateTime.parse(json['created_at'] as String),
      icono: json['icono'] as String?,
      accionUrl: json['accion_url'] as String?,
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
///
/// Implementación offline-first vía Brick (native) con fallback a RPC (web).
final notificacionesProvider =
    FutureProvider<List<NotificacionItem>>((ref) async {
  ref.watch(authStateProvider);
  final empresaId = ref.watch(empresaActivaIdProvider);

  // Web → RPC directa
  if (kIsWeb || empresaId == null) {
    if (empresaId == null) return const [];
    final client = ref.watch(supabaseClientProvider);
    final data = await client.rpc(
      'get_notificaciones',
      params: {'p_limite': 20, 'p_offset': 0},
    );
    return (data as List)
        .map((e) => NotificacionItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Native: Brick offline-first
  final repo = ref.read(repositoryProvider);
  if (repo == null) return const [];

  try {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const [];

    final notifs = await repo.get<Notificacion>(
      policy: OfflineFirstGetPolicy.awaitRemoteWhenNoneExist,
      query: Query(where: [
        Where.exact('empresaId', empresaId),
        Where.exact('usuarioId', session.user.id),
      ]),
    );

    // Ordenar por fecha descendente, limitar a 20
    final sorted = notifs.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));

    return sorted.take(20).map((n) => NotificacionItem(
          id: n.id,
          tipo: n.tipo,
          titulo: n.titulo,
          cuerpo: n.cuerpo,
          leida: n.leida,
          creadaAt: n.createdAt ?? DateTime.now(),
          icono: n.icono,
          accionUrl: n.accionUrl,
        )).toList();
  } catch (_) {
    return const [];
  }
});
