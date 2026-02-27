import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../models/com_conversacion.dart';

// ---------------------------------------------------------------------------
// Conversación seleccionada
// ---------------------------------------------------------------------------

/// ID de la conversación seleccionada en la bandeja. `null` = ninguna.
final convSeleccionadaProvider = StateProvider<String?>((ref) => null);

/// Filtro de canal activo. `null` = todos.
final convFiltroCanal = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// ConversacionesNotifier
// ---------------------------------------------------------------------------

/// Lista de conversaciones para la empresa activa, ordenadas por
/// `ultimo_mensaje_en DESC`.
///
/// Realtime: se suscribe a INSERT/UPDATE en `com_mensajes` para cualquier
/// conversación de la empresa y llama `ref.invalidateSelf()` para re-fetch.
class ConversacionesNotifier
    extends AsyncNotifier<List<ComConversacion>> {
  RealtimeChannel? _channel;
  String? _empresaId;

  @override
  Future<List<ComConversacion>> build() async {
    final empresaId = ref.watch(empresaActivaIdProvider);
    if (empresaId == null) return const [];

    _suscribir(empresaId);

    ref.onDispose(() {
      _channel?.unsubscribe();
      _channel = null;
    });

    final rows = await Supabase.instance.client
        .from('com_conversaciones')
        .select()
        .eq('empresa_id', empresaId)
        .order('ultimo_mensaje_en', ascending: false);

    return (rows as List)
        .map((r) => ComConversacion.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  void _suscribir(String empresaId) {
    if (_empresaId == empresaId) return;
    _channel?.unsubscribe();
    _empresaId = empresaId;

    _channel = Supabase.instance.client
        .channel('com_convs_$empresaId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'com_conversaciones',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'empresa_id',
            value: empresaId,
          ),
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe((status, [_]) {
          // Al reconectar (iOS foreground resume) re-fetch para no perder eventos.
          if (status == RealtimeSubscribeStatus.subscribed) {
            ref.invalidateSelf();
          }
        });
  }
}

final conversacionesProvider =
    AsyncNotifierProvider<ConversacionesNotifier, List<ComConversacion>>(
        ConversacionesNotifier.new);

// ---------------------------------------------------------------------------
// Selector: conversaciones filtradas por canal
// ---------------------------------------------------------------------------

final conversacionesFiltradas =
    Provider<AsyncValue<List<ComConversacion>>>((ref) {
  final todas = ref.watch(conversacionesProvider);
  final canal = ref.watch(convFiltroCanal);

  return todas.whenData(
    (lista) => canal == null
        ? lista
        : lista.where((c) => c.canal == canal).toList(),
  );
});

// ---------------------------------------------------------------------------
// Selector: conversación seleccionada completa
// ---------------------------------------------------------------------------

final convSeleccionadaDetalleProvider =
    Provider<ComConversacion?>((ref) {
  final id = ref.watch(convSeleccionadaProvider);
  if (id == null) return null;
  final todas = ref.watch(conversacionesProvider).valueOrNull ?? const [];
  try {
    return todas.firstWhere((c) => c.id == id);
  } catch (_) {
    return null;
  }
});
