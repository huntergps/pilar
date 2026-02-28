import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/usuario_provider.dart';

// ---------------------------------------------------------------------------
// Canal seleccionado
// ---------------------------------------------------------------------------

/// ID del canal de chat interno seleccionado. `null` = ninguno.
final canalSeleccionadoProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Presencia online
// ---------------------------------------------------------------------------

/// Set de user_id de usuarios actualmente online en el canal seleccionado.
final presenciaProvider = StateProvider<Set<String>>((ref) => const {});

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
/// Cuando el canal seleccionado cambia, cancela el anterior y suscribe al nuevo.
/// Actualiza [presenciaProvider] con el set de usuarios online.
class PresenceNotifier extends Notifier<void> {
  RealtimeChannel? _presenceChannel;

  @override
  void build() {
    final canalId = ref.watch(canalSeleccionadoProvider);
    final empresaId = ref.watch(empresaActivaIdProvider);

    if (canalId == null || empresaId == null) {
      _limpiar();
      return;
    }

    _suscribir(empresaId, canalId);
    ref.onDispose(_limpiar);
  }

  void _suscribir(String empresaId, String canalId) {
    _limpiar();

    final usuarioId = ref.read(usuarioActualProvider)?.id;
    if (usuarioId == null) return;

    final ch = Supabase.instance.client.channel('presence:$empresaId:$canalId');

    ch.onPresenceSync((_) {
      // presenceState() → List<SinglePresenceState>
      // Each .presences → List<Presence>, each .payload → Map<String, dynamic>
      final online = ch
          .presenceState()
          .expand((s) => s.presences)
          .map((p) => p.payload['user_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      ref.read(presenciaProvider.notifier).state = online;
    });

    ch.subscribe((status, [_]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await ch.track({
          'user_id': usuarioId,
          'online_at': DateTime.now().toIso8601String(),
        });
      }
    });

    _presenceChannel = ch;
  }

  void _limpiar() {
    _presenceChannel?.untrack();
    _presenceChannel?.unsubscribe();
    _presenceChannel = null;
    // Reset presence solo si el ref todavía está activo
    try {
      ref.read(presenciaProvider.notifier).state = const {};
    } catch (_) {}
  }
}

final presenceNotifierProvider = NotifierProvider<PresenceNotifier, void>(
  PresenceNotifier.new,
);
