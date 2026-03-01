import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';

// ---------------------------------------------------------------------------
// ComUnreadNotifier — mensajes inbound no leídos + sonido/vibración
// ---------------------------------------------------------------------------

/// Mantiene el conteo de mensajes inbound con estado='recibido' para la
/// empresa activa y suscribe a Realtime para actualizaciones en tiempo real.
///
/// Cuando llega un nuevo mensaje inbound:
///   - Incrementa el conteo (badge en Conversaciones)
///   - Emite sonido de alerta del sistema
///   - Dispara vibración (HapticFeedback)
class ComUnreadNotifier extends StateNotifier<int> {
  ComUnreadNotifier() : super(0);

  RealtimeChannel? _channel;
  String? _empresaId;

  /// Inicializa la suscripción para [empresaId].
  /// Se llama automáticamente cuando cambia la empresa activa.
  Future<void> init(String empresaId) async {
    if (_empresaId == empresaId) return;
    _empresaId = empresaId;

    // Limpiar suscripción anterior
    await _channel?.unsubscribe();
    _channel = null;
    state = 0;

    // Contar mensajes no leídos existentes
    final res = await Supabase.instance.client
        .from('com_mensajes')
        .select()
        .eq('empresa_id', empresaId)
        .eq('tipo', 'inbound')
        .eq('estado', 'recibido')
        .count();
    state = res.count;

    // Suscribir a INSERT de mensajes inbound para la empresa
    _channel = Supabase.instance.client
        .channel('com_unread_$empresaId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'com_mensajes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'empresa_id',
            value: empresaId,
          ),
          callback: (payload) {
            final data = payload.newRecord;
            if (data['tipo'] == 'inbound') {
              state = state + 1;
              _notificar();
            }
          },
        )
        .subscribe();
  }

  /// Reinicia el conteo (llamar al abrir la pantalla de Conversaciones).
  void marcarLeidos() => state = 0;

  void _notificar() {
    // Vibración (iOS + Android)
    HapticFeedback.mediumImpact();
    // Sonido del sistema (iOS + macOS; no-op en Android/Windows)
    SystemSound.play(SystemSoundType.alert);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

final comUnreadProvider =
    StateNotifierProvider<ComUnreadNotifier, int>((ref) {
  final notifier = ComUnreadNotifier();

  // Re-inicializar cuando cambia la empresa activa
  ref.listen<String?>(
    empresaActivaIdProvider,
    (_, next) {
      if (next != null) notifier.init(next);
    },
    fireImmediately: true,
  );

  return notifier;
});
