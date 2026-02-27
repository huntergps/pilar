import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../models/com_mensaje.dart';
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
/// Llama a la RPC `com_get_email_threads` con los filtros activos.
final emailThreadsProvider = FutureProvider.autoDispose
    .family<List<EmailThread>, EmailCarpeta>((ref, carpeta) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return [];

  final busqueda = ref.watch(emailBusquedaProvider);

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

/// Mensajes del hilo seleccionado (reutiliza la RPC existente).
final emailMensajesProvider = FutureProvider.autoDispose
    .family<List<ComMensaje>, String>((ref, convId) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return [];

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
