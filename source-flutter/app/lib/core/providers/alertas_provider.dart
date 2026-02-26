import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';
import 'empresa_provider.dart';
import 'repository_provider.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Alerta persistente de empresa.
///
/// A diferencia de [NotificacionItem] (efímera, por usuario),
/// una alerta permanece activa hasta que alguien la resuelva o ignore.
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

  /// Clave semántica única, p.ej. 'SRI_CERT_EXPIRING'. Puede ser null para
  /// alertas sin deduplicación.
  final String? codigoAlerta;

  /// ID del registro relacionado (soft ref, sin FK).
  final String? registroId;

  /// 'info' | 'warning' | 'error' | 'critical'
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
// Provider — lista de alertas activas
// ---------------------------------------------------------------------------

/// Convierte un [AlertaEmpresa] (Brick) a [AlertaItem] (UI).
/// Los campos no mapeados (datos, registroId, rolesDestino, expiraAt)
/// se inicializan con valores vacíos/nulos aceptables para la presentación.
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

/// Alertas activas visibles para el usuario actual.
///
/// Se invalida al cambiar la sesión o la empresa activa.
/// Usar [alertasCountProvider] para el badge del header.
///
/// Implementación offline-first vía Brick (native) con fallback a RPC (web).
final alertasActivasProvider = FutureProvider<List<AlertaItem>>((ref) async {
  ref.watch(authStateProvider);

  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return const [];

  // Web → RPC directa
  if (kIsWeb) {
    final client = ref.watch(supabaseClientProvider);
    final data = await client.rpc(
      'get_alertas_activas',
      params: {'p_limite': 50, 'p_offset': 0},
    );
    return (data as List)
        .map((e) => AlertaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Native: Brick offline-first
  final repo = ref.read(repositoryProvider);
  if (repo == null) return const [];

  try {
    final alertas = await repo.get<AlertaEmpresa>(
      policy: OfflineFirstGetPolicy.awaitRemoteWhenNoneExist,
      query: Query.where('estado', 'activa'),
    );
    return alertas.map(_alertaFromBrick).toList();
  } catch (_) {
    return const [];
  }
});

// ---------------------------------------------------------------------------
// Provider — conteo en tiempo real (badge del header)
// ---------------------------------------------------------------------------

/// Número de alertas activas visibles para el usuario.
///
/// Estrategia híbrida:
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

  // Realtime: INSERT y UPDATE en alertas_empresa de la empresa activa
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
