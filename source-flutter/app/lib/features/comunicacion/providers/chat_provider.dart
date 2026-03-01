import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/presencia_provider.dart' show EstadoPresencia, estadoPresenciaProvider;
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

  final rows = await Supabase.instance.client.rpc(
    'get_unread_count',
    params: {'p_usuario_id': usuario.id},
  ) as List;

  return rows.cast<Map<String, dynamic>>();
});

// ---------------------------------------------------------------------------
// chatMensajesProvider — mensajes de un canal interno
// ---------------------------------------------------------------------------

/// Mensajes del canal interno [canalId], con suscripción Realtime Broadcast
/// para actualizaciones en tiempo real.
final chatMensajesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
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

  final rows = await Supabase.instance.client
      .from('chat_mensajes')
      .select()
      .eq('canal_id', canalId)
      .order('created_at', ascending: true)
      .limit(200) as List;

  return rows.cast<Map<String, dynamic>>();
});

// ---------------------------------------------------------------------------
// PresenceNotifier — gestiona presencia Realtime para el canal activo
// ---------------------------------------------------------------------------

/// Gestiona el canal de Presencia Supabase para el canal de chat seleccionado.
///
/// - Cuando el canal seleccionado cambia → re-suscribe al nuevo canal Realtime.
/// - Cuando solo cambia el estado (online/ausente/ocupado/noComunicar) →
///   re-trackea sobre el canal existente sin desconectarse.
/// - Actualiza [presenciaProvider] con el mapa userId → EstadoPresencia.
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

    // Solo re-suscribir si cambia el canal o la empresa.
    // Si solo cambia el estado, re-trackear en el canal ya abierto.
    if (canalId != _activeCanalId || empresaId != _activeEmpresaId) {
      _suscribir(empresaId, canalId, estado);
    } else {
      _retrackear(estado);
    }
    ref.onDispose(_limpiar);
  }

  /// Actualiza el payload de presencia sin reconectar el canal.
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
        // Excluir usuarios en modo "No molestar" — no son visibles para otros
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
