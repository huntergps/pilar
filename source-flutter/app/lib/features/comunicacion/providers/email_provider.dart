import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/repository_provider.dart';
import '../models/email_thread.dart';

// ============================================================================
// ENUM: Carpetas de email
// ============================================================================

enum EmailCarpeta {
  recibidos,
  enviados,
  borradores,
  fallidos;

  String get label => switch (this) {
        EmailCarpeta.recibidos => 'Recibidos',
        EmailCarpeta.enviados => 'Enviados',
        EmailCarpeta.borradores => 'Borradores',
        EmailCarpeta.fallidos => 'Fallidos',
      };

  String get rpcKey => switch (this) {
        EmailCarpeta.recibidos => 'recibidos',
        EmailCarpeta.enviados => 'enviados',
        EmailCarpeta.borradores => 'borradores',
        EmailCarpeta.fallidos => 'fallidos',
      };
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Carpeta activa de la bandeja de email.
final emailCarpetaProvider = StateProvider<EmailCarpeta>(
  (ref) => EmailCarpeta.recibidos,
);

/// ID de la conversación seleccionada actualmente.
final emailSeleccionadoProvider = StateProvider<String?>((ref) => null);

/// Texto de búsqueda activo (null = sin filtro).
final emailBusquedaProvider = StateProvider<String?>((ref) => null);

/// Hilos de email para la carpeta indicada.
///
/// emailThreads es una vista derivada (JOIN en RPC), no una tabla directa.
/// Se mantiene como RPC en todas las plataformas.
/// Suscripción Realtime en `com_conversaciones` para actualización automática.
final emailThreadsProvider = FutureProvider.autoDispose
    .family<List<EmailThread>, EmailCarpeta>((ref, carpeta) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return [];

  final busqueda = ref.watch(emailBusquedaProvider);

  // Realtime: re-fetch cuando cambia cualquier conversación de la empresa.
  final channel = Supabase.instance.client
      .channel('email_threads_${empresaId}_${carpeta.rpcKey}')
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
      .subscribe();
  ref.onDispose(() => channel.unsubscribe());

  final params = <String, dynamic>{
    'p_carpeta': carpeta.rpcKey,
    'p_limit': 50,
    'p_offset': 0,
  };
  if (busqueda != null && busqueda.isNotEmpty) {
    params['p_busqueda'] = busqueda;
  }

  final data =
      await Supabase.instance.client.rpc('com_get_email_threads', params: params);

  return (data as List)
      .map((e) => EmailThread.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Mensajes del hilo seleccionado.
///
/// - **Native**: Lee desde SQLite (Brick) por `conversacionId`, con fallback
///   a RPC `com_get_mensajes_conversacion`.
/// - **Web**: RPC directa.
///
/// Suscripción Realtime a `com_mensajes` para actualización automática
/// cuando llegan respuestas. Incluye reconexión automática.
final emailMensajesProvider = FutureProvider.autoDispose
    .family<List<ComMensaje>, String>((ref, convId) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return [];

  var esInicial = true;

  final channel = Supabase.instance.client
      .channel('email_msgs_$convId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'com_mensajes',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversacion_id',
          value: convId,
        ),
        callback: (_) => ref.invalidateSelf(),
      )
      .subscribe((status, [_]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (esInicial) {
            esInicial = false;
          } else {
            ref.invalidateSelf();
          }
        }
      });
  ref.onDispose(() => channel.unsubscribe());

  // Native: local-first con Brick
  final repo = ref.read(repositoryProvider);
  if (!kIsWeb && repo != null) {
    try {
      final results = await repo.get<ComMensaje>(
        policy: OfflineFirstGetPolicy.awaitRemote,
        query: Query(where: [Where.exact('conversacionId', convId)]),
      );
      if (results.isNotEmpty) {
        return results..sort((a, b) {
          final ta = a.creadoEn;
          final tb = b.creadoEn;
          if (ta == null && tb == null) return 0;
          if (ta == null) return -1;
          if (tb == null) return 1;
          return ta.compareTo(tb);
        });
      }
    } catch (_) {
      // fall through to RPC
    }
  }

  // Web fallback o si Brick no tiene datos
  final data = await Supabase.instance.client.rpc(
    'com_get_mensajes_conversacion',
    params: {'p_conv_id': convId, 'p_limit': 100, 'p_offset': 0},
  );

  return (data as List)
      .map((e) => ComMensaje.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Cuentas de email disponibles para envío (email_api / email_smtp).
final emailCuentasProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return [];

  final data = await Supabase.instance.client
      .from('com_cuentas')
      .select('id, nombre, tipo')
      .eq('empresa_id', empresaId)
      .eq('activo', true)
      .inFilter('tipo', ['email_api', 'email_smtp'])
      .order('nombre');

  return (data as List).cast<Map<String, dynamic>>();
});

// ---------------------------------------------------------------------------
// EnviarEmailNotifier — escritura de mensajes de email
// ---------------------------------------------------------------------------

/// Notifier para enviar emails outbound vía com_mensajes.
///
/// Uso:
/// ```dart
/// await ref.read(enviarEmailProvider.notifier).enviar(
///   cuentaId: id,
///   to: 'dest@example.com',
///   subject: 'Asunto',
///   body: '<p>Cuerpo</p>',
/// );
/// ```
class EnviarEmailNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> enviar({
    required String cuentaId,
    required String to,
    required String subject,
    required String body,
    String? conversacionId,
  }) async {
    final empresaId = ref.read(empresaActivaIdProvider);

    await Supabase.instance.client.from('com_mensajes').insert({
      'empresa_id': empresaId,
      'cuenta_id': cuentaId,
      'canal': 'email_api',
      'tipo': 'outbound',
      'destinatario_ref': to,
      'asunto': subject,
      'cuerpo': body,
      if (conversacionId != null) 'conversacion_id': conversacionId,
    });

    // Invalidar hilos y mensajes para reflejar el envío
    ref.invalidate(emailThreadsProvider);
    if (conversacionId != null) {
      ref.invalidate(emailMensajesProvider(conversacionId));
    }
  }
}

final enviarEmailProvider =
    AsyncNotifierProvider<EnviarEmailNotifier, void>(EnviarEmailNotifier.new);
