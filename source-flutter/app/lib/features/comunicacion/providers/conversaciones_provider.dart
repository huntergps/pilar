import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/repository_provider.dart';

// ---------------------------------------------------------------------------
// Cuentas outbound (para nueva conversación)
// ---------------------------------------------------------------------------

/// Registra un tipo de cuenta accesible para enviar mensajes.
typedef CuentaOutbound = ({String id, String nombre, String tipo});

/// Cuentas de WhatsApp y Telegram activas accesibles al usuario actual.
/// Usado en el diálogo de nueva conversación outbound.
final cuentasOutboundProvider =
    FutureProvider.autoDispose<List<CuentaOutbound>>((ref) async {
  final session = Supabase.instance.client.auth.currentSession;
  final empresaId = session?.user.appMetadata['empresa_id'] as String?;
  if (empresaId == null) return [];

  try {
    final data = await Supabase.instance.client
        .rpc('com_get_todas_cuentas') as List;
    return data
        .cast<Map<String, dynamic>>()
        .where((m) =>
            (m['activo'] as bool? ?? false) &&
            ['whatsapp', 'telegram'].contains(m['tipo']))
        .map((m) => (
              id: m['id'] as String,
              nombre: m['nombre'] as String? ?? '',
              tipo: m['tipo'] as String? ?? '',
            ))
        .toList();
  } catch (_) {
    final data = await Supabase.instance.client
        .from('com_cuentas')
        .select('id, nombre, tipo')
        .eq('empresa_id', empresaId)
        .eq('activo', true)
        .inFilter('tipo', ['whatsapp', 'telegram'])
        .order('nombre') as List;
    return data
        .cast<Map<String, dynamic>>()
        .map((m) => (
              id: m['id'] as String,
              nombre: m['nombre'] as String? ?? '',
              tipo: m['tipo'] as String? ?? '',
            ))
        .toList();
  }
});

// ---------------------------------------------------------------------------
// Conversación seleccionada
// ---------------------------------------------------------------------------

/// ID de la conversación seleccionada en la bandeja. `null` = ninguna.
final convSeleccionadaProvider = StateProvider<String?>((ref) => null);

/// Filtro de canal activo. `null` = todos.
final convFiltroCanal = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// ConversacionesNotifier — offline-first
// ---------------------------------------------------------------------------

/// Lista de conversaciones para la empresa activa, ordenadas por
/// `ultimo_mensaje_en DESC`.
///
/// - **Native**: Lee desde SQLite (Brick) + background sync desde Supabase.
/// - **Web**: RPC `com_get_conversaciones` directa.
///
/// Realtime: se suscribe a INSERT/UPDATE en `com_conversaciones` para cualquier
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

    // Native: local-first con Brick (offline disponible)
    final repo = ref.read(repositoryProvider);
    if (!kIsWeb && repo != null) {
      return _fetchNative(repo, empresaId);
    }

    // Web fallback: RPC
    return _fetchRpc();
  }

  Future<List<ComConversacion>> _fetchNative(
      PilarRepository repo, String empresaId) async {
    try {
      final results = await repo.get<ComConversacion>(
        policy: OfflineFirstGetPolicy.awaitRemote,
        query: Query(where: [Where.exact('activa', true)]),
      );
      return results
        ..sort((a, b) {
          final ta = a.ultimoMensajeEn;
          final tb = b.ultimoMensajeEn;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
    } catch (_) {
      return _fetchRpc();
    }
  }

  Future<List<ComConversacion>> _fetchRpc() async {
    final rows = await Supabase.instance.client.rpc(
      'com_get_conversaciones',
      params: {'p_activas': true, 'p_limit': 100, 'p_offset': 0},
    ) as List;
    return rows
        .map((r) => ComConversacion.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // -------------------------------------------------------------------------
  // Métodos de escritura
  // -------------------------------------------------------------------------

  /// Envía un mensaje outbound a una conversación existente.
  Future<void> enviarMensaje(ComConversacion conv, String texto) async {
    final empresaId = ref.read(empresaActivaIdProvider);
    if (empresaId == null) return;

    await Supabase.instance.client.from('com_mensajes').insert({
      'empresa_id': empresaId,
      'cuenta_id': conv.cuentaId,
      'conversacion_id': conv.id,
      'tipo': 'outbound',
      'canal': conv.canal,
      'destinatario_ref': conv.destinatarioRef,
      'cuerpo': texto,
      'estado': 'pendiente',
    });
    invocarSender(conv.canal);
  }

  /// Crea o reutiliza una conversación y envía el mensaje inicial.
  /// Retorna el [conversacion_id].
  Future<String> iniciarConversacion({
    required String empresaId,
    required String cuentaId,
    required String canal,
    required String destinatarioRef,
    String? destinatarioNombre,
    String? contactoId,
    required String cuerpo,
  }) async {
    final convData = await Supabase.instance.client
        .from('com_conversaciones')
        .upsert(
          {
            'empresa_id': empresaId,
            'cuenta_id': cuentaId,
            'canal': canal,
            'destinatario_ref': destinatarioRef,
            if (destinatarioNombre?.isNotEmpty == true)
              'destinatario_nombre': destinatarioNombre,
            if (contactoId != null) 'contacto_id': contactoId,
            'activo': true,
            'ultimo_mensaje_en': DateTime.now().toIso8601String(),
          },
          onConflict: 'empresa_id,cuenta_id,destinatario_ref',
        )
        .select('id')
        .single();

    final convId = convData['id'] as String;

    await Supabase.instance.client.from('com_mensajes').insert({
      'empresa_id': empresaId,
      'cuenta_id': cuentaId,
      'conversacion_id': convId,
      'tipo': 'outbound',
      'canal': canal,
      'destinatario_ref': destinatarioRef,
      'cuerpo': cuerpo,
      'estado': 'pendiente',
    });

    invocarSender(canal);
    ref.invalidateSelf();
    return convId;
  }

  /// Desvincula una conversación de la entidad de negocio asociada.
  Future<void> desvincularConversacion(String convId) async {
    await Supabase.instance.client.rpc(
      'com_desvincular_conversacion',
      params: {'p_conversacion_id': convId},
    );
    ref.invalidateSelf();
  }

  /// Invoca el Edge Function sender del canal. Fire-and-forget.
  void invocarSender(String canal) {
    final fnName = switch (canal) {
      'telegram' => 'com-telegram-sender',
      'whatsapp' => 'com-whatsapp-sender',
      _ => null,
    };
    if (fnName == null) return;
    Supabase.instance.client.functions.invoke(fnName, body: {}).ignore();
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
