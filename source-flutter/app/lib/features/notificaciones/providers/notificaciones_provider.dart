import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/repository_provider.dart';
import '../../../core/offline/connectivity_service.dart';

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
  final String tipo;
  final String titulo;
  final String? cuerpo;
  final bool leida;
  final DateTime creadaAt;
  final String? icono;
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

/// Numero de notificaciones no leidas. Estrategia híbrida:
/// 1. Fetch inicial via RPC.
/// 2. Realtime INSERT en notificaciones_usuario → re-fetch.
/// 3. Refresh periódico cada 30 s como fallback.
final notificacionesBadgeProvider = StreamProvider<int>((ref) async* {
  ref.watch(authStateProvider);
  final empresaId = ref.watch(empresaActivaIdProvider);

  if (empresaId == null) {
    yield 0;
    return;
  }

  final client = ref.watch(supabaseClientProvider);
  final controller = StreamController<int>();

  Future<void> fetchCount() async {
    try {
      final result = await client.rpc('get_count_notificaciones_no_leidas');
      if (!controller.isClosed) {
        controller.add((result as int?) ?? 0);
      }
    } catch (_) {}
  }

  await fetchCount();

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

  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (!controller.isClosed) fetchCount();
  });

  ref.onDispose(() {
    timer.cancel();
    channel.unsubscribe();
    controller.close();
  });

  yield* controller.stream;
});

// ---------------------------------------------------------------------------
// Lista de notificaciones (local-first + background sync)
// ---------------------------------------------------------------------------

/// Últimas 20 notificaciones del usuario.
///
/// Patrón local-first + background sync:
/// 1. Emite desde SQLite (Brick) inmediatamente.
/// 2. Sincroniza en background desde Supabase.
/// 3. Emite datos actualizados.
///
/// Invalidar manualmente tras marcar notificación como leída:
/// ```dart
/// ref.invalidate(notificacionesProvider);
/// ```
final notificacionesProvider = StreamProvider<List<NotificacionItem>>((ref) async* {
  ref.watch(authStateProvider);
  final empresaId = ref.watch(empresaActivaIdProvider);

  // Web: RPC directa
  if (kIsWeb || empresaId == null) {
    if (empresaId == null) { yield const []; return; }
    final client = ref.watch(supabaseClientProvider);
    try {
      final data = await client.rpc(
        'get_notificaciones',
        params: {'p_limite': 20, 'p_offset': 0},
      );
      yield (data as List)
          .map((e) => NotificacionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      yield const <NotificacionItem>[];
    }
    return;
  }

  // Native: local-first + background sync
  final repo = ref.read(repositoryProvider);
  if (repo == null) { yield const []; return; }

  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) { yield const []; return; }

  final query = Query(where: [
    Where.exact('empresaId', empresaId),
    Where.exact('usuarioId', session.user.id),
  ]);

  NotificacionItem fromBrick(Notificacion n) => NotificacionItem(
        id: n.id,
        tipo: n.tipo,
        titulo: n.titulo,
        cuerpo: n.cuerpo,
        leida: n.leida,
        creadaAt: n.createdAt ?? DateTime.now(),
        icono: n.icono,
        accionUrl: n.accionUrl,
      );

  List<NotificacionItem> sortAndLimit(List<Notificacion> notifs) {
    final sorted = notifs.toList()
      ..sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return sorted.take(20).map(fromBrick).toList();
  }

  // 1. Local primero
  try {
    final local = await repo.get<Notificacion>(
      policy: OfflineFirstGetPolicy.localOnly,
      query: query,
    );
    yield sortAndLimit(local);
  } catch (_) {
    yield const <NotificacionItem>[];
  }

  // 2. Background sync
  try {
    final fresh = await repo.get<Notificacion>(
      policy: OfflineFirstGetPolicy.awaitRemote,
      query: query,
    );
    yield sortAndLimit(fresh);
    ref.read(connectivityProvider.notifier).reportOnline();
  } catch (e) {
    if (isOfflineError(e)) {
      ref.read(connectivityProvider.notifier).reportOffline();
    }
  }
});
