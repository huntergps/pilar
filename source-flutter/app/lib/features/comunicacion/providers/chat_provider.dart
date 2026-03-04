import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/presencia_provider.dart' show EstadoPresencia, estadoPresenciaProvider;
import '../../../core/providers/repository_provider.dart';
import '../../../core/providers/usuario_provider.dart';

// ---------------------------------------------------------------------------
// Canal seleccionado
// ---------------------------------------------------------------------------

/// ID del canal de chat interno seleccionado. `null` = ninguno.
final canalSeleccionadoProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Presencia online
// ---------------------------------------------------------------------------

/// Mapa user_id → EstadoPresencia de usuarios online en el canal seleccionado.
/// Solo incluye usuarios con estado visible (excluye [EstadoPresencia.noComunicar]).
final presenciaProvider = StateProvider<Map<String, EstadoPresencia>>((ref) => const {});

// ---------------------------------------------------------------------------
// empresaMiembrosProvider — usuarios activos de la empresa (para DM picker)
// ---------------------------------------------------------------------------

/// Lista de miembros activos de la empresa activa, excluyendo al usuario actual.
/// Retorna [{usuario_id, nombre_display, email}] vía RPC get_empresa_miembros.
final empresaMiembrosProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.watch(empresaActivaIdProvider); // re-fetch al cambiar empresa

  final result =
      await Supabase.instance.client.rpc('get_empresa_miembros') as List;

  return result.cast<Map<String, dynamic>>();
});

// ---------------------------------------------------------------------------
// chatCanalesProvider — lista de canales con badge de no leídos
// ---------------------------------------------------------------------------

/// Canales de chat interno de la empresa activa, con conteo de mensajes
/// no leídos para el usuario actual.
///
/// RPC: `comunicacion.get_unread_count(p_usuario_id UUID)`
/// Retorna: `[{canal_id, nombre, tipo, no_leidos, ultimo_mensaje, ultimo_mensaje_en}]`
final chatCanalesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return const [];

  final usuario = ref.watch(usuarioActualProvider);
  if (usuario == null) return const [];

  final canalActivo = ref.watch(canalSeleccionadoProvider);

  if (canalActivo != null) {
    final channel = Supabase.instance.client
        .channel('chat:$empresaId:$canalActivo')
        .onBroadcast(
          event: 'new_message',
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();
    ref.onDispose(() => channel.unsubscribe());
  }

  final rows = await Supabase.instance.client.rpc(
    'get_unread_count',
    params: {'p_usuario_id': usuario.id},
  ) as List;

  return rows.cast<Map<String, dynamic>>();
});

// ---------------------------------------------------------------------------
// chatMensajesProvider — mensajes de un canal interno (offline-first)
// ---------------------------------------------------------------------------

/// Mensajes del canal interno [canalId].
///
/// - **Native**: Lee desde SQLite (Brick) + background sync desde Supabase.
/// - **Web**: Directo desde tabla `chat_mensajes`.
///
/// Suscripción Realtime Broadcast para actualizaciones en tiempo real.
final chatMensajesProvider =
    FutureProvider.autoDispose.family<List<ChatMensaje>, String>(
        (ref, canalId) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return const [];

  // Suscripción Realtime Broadcast para mensajes nuevos.
  final channel = Supabase.instance.client
      .channel('chat:$empresaId:$canalId')
      .onBroadcast(
        event: 'new_message',
        callback: (_) => ref.invalidateSelf(),
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
  });

  // Native: local-first con Brick
  final repo = ref.read(repositoryProvider);
  if (!kIsWeb && repo != null) {
    try {
      final results = await repo.get<ChatMensaje>(
        policy: OfflineFirstGetPolicy.awaitRemote,
        query: Query(
          where: [Where.exact('canalId', canalId)],
          orderBy: [const OrderBy('createdAt', ascending: true)],
          limit: 200,
        ),
      );
      if (results.isNotEmpty) return results;
    } catch (_) {
      // fall through to direct query
    }
  }

  // Web fallback o si Brick no tiene datos
  final rows = await Supabase.instance.client
      .from('chat_mensajes')
      .select()
      .eq('canal_id', canalId)
      .order('created_at', ascending: true)
      .limit(200) as List;

  return rows
      .cast<Map<String, dynamic>>()
      .map((r) => ChatMensaje(
            id: r['id'] as String,
            canalId: r['canal_id'] as String,
            usuarioId: r['usuario_id'] as String,
            cuerpo: r['cuerpo'] as String?,
            createdAt: r['created_at'] != null
                ? DateTime.parse(r['created_at'] as String)
                : null,
          ))
      .toList();
});

// ---------------------------------------------------------------------------
// PresenceNotifier — gestiona presencia Realtime para el canal activo
// ---------------------------------------------------------------------------

/// Gestiona el canal de Presencia Supabase para el canal de chat seleccionado.
class PresenceNotifier extends Notifier<void> {
  RealtimeChannel? _presenceChannel;
  String? _activeCanalId;
  String? _activeEmpresaId;

  @override
  void build() {
    final canalId = ref.watch(canalSeleccionadoProvider);
    final empresaId = ref.watch(empresaActivaIdProvider);
    final estado = ref.watch(estadoPresenciaProvider);

    if (canalId == null || empresaId == null) {
      _limpiar();
      return;
    }

    if (canalId != _activeCanalId || empresaId != _activeEmpresaId) {
      _suscribir(empresaId, canalId, estado);
    } else {
      _retrackear(estado);
    }
    ref.onDispose(_limpiar);
  }

  void _retrackear(EstadoPresencia estado) {
    final ch = _presenceChannel;
    if (ch == null) return;
    final usuarioId = ref.read(usuarioActualProvider)?.id;
    if (usuarioId == null) return;
    ch.track({
      'user_id': usuarioId,
      'online_at': DateTime.now().toIso8601String(),
      'estado': estado.name,
    });
  }

  void _suscribir(String empresaId, String canalId, EstadoPresencia estado) {
    _limpiar();
    _activeCanalId = canalId;
    _activeEmpresaId = empresaId;

    final usuarioId = ref.read(usuarioActualProvider)?.id;
    if (usuarioId == null) return;

    final ch = Supabase.instance.client.channel('presence:$empresaId:$canalId');

    ch.onPresenceSync((_) {
      final mapa = <String, EstadoPresencia>{};
      for (final p in ch.presenceState().expand((s) => s.presences)) {
        final userId = p.payload['user_id'] as String? ?? '';
        if (userId.isEmpty) continue;
        final estadoStr = p.payload['estado'] as String? ?? 'online';
        final e = EstadoPresencia.values.firstWhere(
          (e) => e.name == estadoStr,
          orElse: () => EstadoPresencia.online,
        );
        if (e != EstadoPresencia.noComunicar) {
          mapa[userId] = e;
        }
      }
      ref.read(presenciaProvider.notifier).state = mapa;
    });

    ch.subscribe((status, [_]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await ch.track({
          'user_id': usuarioId,
          'online_at': DateTime.now().toIso8601String(),
          'estado': estado.name,
        });
      }
    });

    _presenceChannel = ch;
  }

  void _limpiar() {
    _presenceChannel?.untrack();
    _presenceChannel?.unsubscribe();
    _presenceChannel = null;
    _activeCanalId = null;
    _activeEmpresaId = null;
    try {
      ref.read(presenciaProvider.notifier).state = const <String, EstadoPresencia>{};
    } catch (_) {}
  }
}

final presenceNotifierProvider = NotifierProvider<PresenceNotifier, void>(
  PresenceNotifier.new,
);

// ---------------------------------------------------------------------------
// ChatActionsNotifier — operaciones de escritura del chat interno
// ---------------------------------------------------------------------------

/// Notifier para operaciones de escritura del chat: crear canales,
/// enviar mensajes y marcar como leídos.
///
/// Uso:
/// ```dart
/// final canalId = await ref.read(chatActionsProvider.notifier).crearCanalGrupo(
///   nombre: 'ventas',
///   miembroIds: ['uuid1', 'uuid2'],
/// );
/// await ref.read(chatActionsProvider.notifier).enviarMensaje(
///   canalId: id, cuerpo: texto,
/// );
/// ```
class ChatActionsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Crea un canal de grupo y retorna el [canal_id] generado.
  Future<String> crearCanalGrupo({
    required String nombre,
    required List<String> miembroIds,
  }) async {
    final result = await Supabase.instance.client.rpc(
      'create_canal_grupo',
      params: {
        'p_nombre': nombre,
        'p_miembro_ids': miembroIds,
      },
    ) as Map<String, dynamic>;
    ref.invalidate(chatCanalesProvider);
    return result['canal_id'] as String;
  }

  /// Obtiene o crea el DM con [otroUserId] y retorna el [canal_id].
  Future<String> getOrCreateDm(String otroUserId) async {
    final result = await Supabase.instance.client.rpc(
      'get_or_create_dm_canal',
      params: {'p_otro_usuario_id': otroUserId},
    ) as Map<String, dynamic>;
    return result['canal_id'] as String;
  }

  /// Marca los mensajes del canal [canalId] como leídos para el usuario actual.
  Future<void> marcarLeido(String canalId) async {
    final usuarioId = ref.read(usuarioActualProvider)?.id;
    if (usuarioId == null) return;
    await Supabase.instance.client.rpc(
      'mark_messages_read',
      params: {'canal_id': canalId, 'usuario_id': usuarioId},
    );
    ref.invalidate(chatCanalesProvider);
  }

  /// Envía un mensaje de texto al canal [canalId].
  Future<void> enviarMensaje({
    required String canalId,
    required String cuerpo,
  }) async {
    final usuarioId = ref.read(usuarioActualProvider)?.id;
    final empresaId = ref.read(empresaActivaIdProvider);
    if (usuarioId == null || empresaId == null) return;

    await Supabase.instance.client.from('chat_mensajes').insert({
      'canal_id': canalId,
      'user_id': usuarioId,
      'empresa_id': empresaId,
      'cuerpo': cuerpo,
      'tipo': 'texto',
    });
    ref.invalidate(chatMensajesProvider(canalId));
  }
}

final chatActionsProvider =
    AsyncNotifierProvider<ChatActionsNotifier, void>(ChatActionsNotifier.new);
