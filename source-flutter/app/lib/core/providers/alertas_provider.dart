import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';
import 'empresa_provider.dart';
import '../offline/connectivity_service.dart';
import 'repository_provider.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Alerta persistente de empresa.
class AlertaItem {
  const AlertaItem({
    required this.id,
    required this.origenModulo,
    this.codigoAlerta,
    this.registroId,
    required this.severidad,
    required this.titulo,
    this.cuerpo,
    required this.datos,
    this.accionUrl,
    this.rolesDestino,
    this.expiraAt,
    required this.creadaAt,
  });

  final String id;
  final String origenModulo;
  final String? codigoAlerta;
  final String? registroId;
  final String severidad;
  final String titulo;
  final String? cuerpo;
  final Map<String, dynamic> datos;
  final String? accionUrl;
  final List<String>? rolesDestino;
  final DateTime? expiraAt;
  final DateTime creadaAt;

  factory AlertaItem.fromJson(Map<String, dynamic> json) {
    return AlertaItem(
      id:            json['id'] as String,
      origenModulo:  json['origen_modulo'] as String? ?? 'sistema',
      codigoAlerta:  json['codigo_alerta'] as String?,
      registroId:    json['registro_id'] as String?,
      severidad:     json['severidad'] as String? ?? 'warning',
      titulo:        json['titulo'] as String,
      cuerpo:        json['cuerpo'] as String?,
      datos:         (json['datos'] as Map<String, dynamic>?) ?? {},
      accionUrl:     json['accion_url'] as String?,
      rolesDestino:  (json['roles_destino'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      expiraAt: json['expira_at'] != null
          ? DateTime.parse(json['expira_at'] as String)
          : null,
      creadaAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

AlertaItem _alertaFromBrick(AlertaEmpresa a) => AlertaItem(
      id: a.id,
      origenModulo: a.origenModulo,
      codigoAlerta: a.codigoAlerta,
      registroId: null,
      severidad: a.severidad,
      titulo: a.titulo,
      cuerpo: a.cuerpo,
      datos: const {},
      accionUrl: a.accionUrl,
      rolesDestino: null,
      expiraAt: null,
      creadaAt: a.createdAt ?? DateTime.now(),
    );

// ---------------------------------------------------------------------------
// Provider — lista de alertas activas (local-first + background sync)
// ---------------------------------------------------------------------------

/// Alertas activas visibles para el usuario actual.
///
/// Patrón local-first + background sync:
/// 1. Emite alertas de SQLite (Brick) inmediatamente.
/// 2. Sincroniza en background desde Supabase.
/// 3. Emite datos actualizados.
final alertasActivasProvider = StreamProvider<List<AlertaItem>>((ref) async* {
  ref.watch(authStateProvider);
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) { yield const []; return; }

  // Web: RPC directa
  if (kIsWeb) {
    final client = ref.watch(supabaseClientProvider);
    try {
      final data = await client.rpc(
        'get_alertas_activas',
        params: {'p_limite': 50, 'p_offset': 0},
      );
      yield (data as List)
          .map((e) => AlertaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      yield const <AlertaItem>[];
    }
    return;
  }

  // Native: local-first + background sync
  final repo = ref.read(repositoryProvider);
  if (repo == null) { yield const []; return; }

  final query = Query(where: [
    Where.exact('empresaId', empresaId),
    const Where.exact('estado', 'activa'),
  ]);

  // 1. Local primero
  try {
    final local = await repo.get<AlertaEmpresa>(
      policy: OfflineFirstGetPolicy.localOnly,
      query: query,
    );
    yield local.map(_alertaFromBrick).toList();
  } catch (_) {
    yield const <AlertaItem>[];
  }

  // 2. Background sync
  try {
    final fresh = await repo.get<AlertaEmpresa>(
      policy: OfflineFirstGetPolicy.awaitRemote,
      query: query,
    );
    yield fresh.map(_alertaFromBrick).toList();
    ref.read(connectivityProvider.notifier).reportOnline();
  } catch (e) {
    if (isOfflineError(e)) {
      ref.read(connectivityProvider.notifier).reportOffline();
    }
  }
});

// ---------------------------------------------------------------------------
// Provider — conteo en tiempo real (badge del header)
// ---------------------------------------------------------------------------

/// Número de alertas activas. Estrategia híbrida:
/// 1. Fetch inicial via RPC.
/// 2. Realtime INSERT/UPDATE en alertas_empresa → re-fetch.
/// 3. Refresh periódico cada 60 s como fallback.
final alertasCountProvider = StreamProvider<int>((ref) async* {
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
      final result = await client.rpc('get_count_alertas_activas');
      if (!controller.isClosed) {
        controller.add((result as int?) ?? 0);
      }
    } catch (_) {}
  }

  await fetchCount();

  final channel = client
      .channel('alertas_count_$empresaId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'alertas_empresa',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'empresa_id',
          value: empresaId,
        ),
        callback: (_) => fetchCount(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'alertas_empresa',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'empresa_id',
          value: empresaId,
        ),
        callback: (_) => fetchCount(),
      )
      .subscribe();

  final timer = Timer.periodic(const Duration(seconds: 60), (_) {
    if (!controller.isClosed) fetchCount();
  });

  ref.onDispose(() {
    timer.cancel();
    channel.unsubscribe();
    controller.close();
  });

  yield* controller.stream;
});
