// Providers del Chatter (Foundation layer).
//
// Todos los providers son family por ChatterRef = ({entidadTipo, entidadId}).
// ChatterNotifier subscribe a Realtime para actualizaciones en tiempo real.

import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart' show immutable, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chatter_actividad.dart';
import 'repository_provider.dart';

// ---------------------------------------------------------------------------
// Parámetro de identidad
// ---------------------------------------------------------------------------

/// Tupla que identifica de forma única el registro al que pertenece el chatter.
typedef ChatterRef = ({String entidadTipo, String entidadId});

// ---------------------------------------------------------------------------
// Provider de mensajes (con Realtime)
// ---------------------------------------------------------------------------

class ChatterNotifier
    extends FamilyAsyncNotifier<List<ChatterMensaje>, ChatterRef> {
  RealtimeChannel? _channel;

  @override
  Future<List<ChatterMensaje>> build(ChatterRef arg) async {
    // Cancelar suscripción anterior al reconstruir
    ref.onDispose(() {
      _channel?.unsubscribe();
      _channel = null;
    });

    // Suscribir Realtime para INSERT en chatter_mensajes
    final client = Supabase.instance.client;
    _channel = client
        .channel('chatter_${arg.entidadTipo}_${arg.entidadId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chatter_mensajes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'entidad_id',
            value: arg.entidadId,
          ),
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();

    // Native: local-first con Brick
    final repo = ref.read(repositoryProvider);
    if (!kIsWeb && repo != null) {
      try {
        final results = await repo.get<ChatterMensaje>(
          policy: OfflineFirstGetPolicy.awaitRemote,
          query: Query(where: [
            Where.exact('entidadTipo', arg.entidadTipo),
            Where.exact('entidadId', arg.entidadId),
          ]),
        );
        if (results.isNotEmpty) {
          return results
            ..sort((a, b) {
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

    return _fetchMensajes(arg);
  }

  // -------------------------------------------------------------------------
  // Acciones
  // -------------------------------------------------------------------------

  /// Publica un mensaje en el chatter del registro.
  Future<void> postMensaje({
    required String cuerpo,
    String subtype = 'discusion',
    List<String> adjuntosIds = const [],
  }) async {
    final arg = this.arg;
    await Supabase.instance.client.rpc(
      'chatter_post_mensaje',
      params: {
        'p_entidad_tipo': arg.entidadTipo,
        'p_entidad_id': arg.entidadId,
        'p_cuerpo': cuerpo,
        'p_subtype': subtype,
        'p_adjuntos_ids': adjuntosIds,
        'p_es_interno': subtype == 'nota_interna',
      },
    );
    // Realtime dispara la actualización; también invalidamos como fallback
    ref.invalidateSelf();
  }

  /// Fuerza recarga de mensajes.
  Future<void> refresh() async => ref.invalidateSelf();

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Future<List<ChatterMensaje>> _fetchMensajes(ChatterRef arg) async {
    final rows = await Supabase.instance.client.rpc(
      'chatter_get_mensajes',
      params: {
        'p_entidad_tipo': arg.entidadTipo,
        'p_entidad_id': arg.entidadId,
        'p_limit': 100,
        'p_offset': 0,
        'p_incluir_logs': true,
      },
    );

    return (rows as List<dynamic>)
        .map((r) => ChatterMensaje.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

final chatterProvider = AsyncNotifierProvider.family<
    ChatterNotifier,
    List<ChatterMensaje>,
    ChatterRef>(
  ChatterNotifier.new,
);

// ---------------------------------------------------------------------------
// Provider de actividades
// ---------------------------------------------------------------------------

/// Actividades pendientes o todas del registro.
///
/// Uso: `ref.watch(chatterActividadesProvider((entidadTipo: 'facturas', entidadId: id)))`
final chatterActividadesProvider =
    FutureProvider.family<List<ChatterActividad>, ChatterRef>(
  (ref, arg) async {
    final rows = await Supabase.instance.client.rpc(
      'chatter_get_actividades',
      params: {
        'p_entidad_tipo': arg.entidadTipo,
        'p_entidad_id': arg.entidadId,
        'p_solo_pendientes': false,
      },
    );

    return (rows as List<dynamic>)
        .map((r) => ChatterActividad.fromJson(r as Map<String, dynamic>))
        .toList();
  },
);

/// Solo actividades pendientes — para badges.
final chatterActividadesPendientesProvider =
    FutureProvider.family<List<ChatterActividad>, ChatterRef>(
  (ref, arg) async {
    final rows = await Supabase.instance.client.rpc(
      'chatter_get_actividades',
      params: {
        'p_entidad_tipo': arg.entidadTipo,
        'p_entidad_id': arg.entidadId,
        'p_solo_pendientes': true,
      },
    );

    return (rows as List<dynamic>)
        .map((r) => ChatterActividad.fromJson(r as Map<String, dynamic>))
        .toList();
  },
);

// ---------------------------------------------------------------------------
// Provider de seguimiento
// ---------------------------------------------------------------------------

/// ¿El usuario actual sigue este registro?
///
/// Uso: `ref.watch(chatterEsSeguidorProvider((entidadTipo: 'facturas', entidadId: id)))`
final chatterEsSeguidorProvider =
    FutureProvider.family<bool, ChatterRef>((ref, arg) async {
  final result = await Supabase.instance.client.rpc(
    'chatter_is_seguidor',
    params: {
      'p_entidad_tipo': arg.entidadTipo,
      'p_entidad_id': arg.entidadId,
    },
  );
  return (result as bool?) ?? false;
});

// ---------------------------------------------------------------------------
// Provider de acciones de seguimiento (Notifier simple)
// ---------------------------------------------------------------------------

class ChatterSeguimientoNotifier
    extends FamilyNotifier<void, ChatterRef> {
  @override
  void build(ChatterRef arg) {}

  Future<void> seguir() async {
    await Supabase.instance.client.rpc(
      'chatter_seguir',
      params: {
        'p_entidad_tipo': arg.entidadTipo,
        'p_entidad_id': arg.entidadId,
      },
    );
    ref.invalidate(chatterEsSeguidorProvider(arg));
  }

  Future<void> dejarDeSeguir() async {
    await Supabase.instance.client.rpc(
      'chatter_dejar_de_seguir',
      params: {
        'p_entidad_tipo': arg.entidadTipo,
        'p_entidad_id': arg.entidadId,
      },
    );
    ref.invalidate(chatterEsSeguidorProvider(arg));
  }
}

final chatterSeguimientoProvider = NotifierProvider.family<
    ChatterSeguimientoNotifier,
    void,
    ChatterRef>(
  ChatterSeguimientoNotifier.new,
);

// ---------------------------------------------------------------------------
// Provider de acciones de actividades
// ---------------------------------------------------------------------------

class ChatterActividadesNotifier
    extends FamilyAsyncNotifier<List<ChatterActividad>, ChatterRef> {
  @override
  Future<List<ChatterActividad>> build(ChatterRef arg) async {
    return _fetch(arg);
  }

  Future<void> crearActividad({
    required String titulo,
    required String tipo,
    required DateTime fechaLimite,
    String? descripcion,
    String? asignadoA,
  }) async {
    await Supabase.instance.client.rpc(
      'chatter_crear_actividad',
      params: {
        'p_entidad_tipo': arg.entidadTipo,
        'p_entidad_id': arg.entidadId,
        'p_titulo': titulo,
        'p_tipo': tipo,
        'p_fecha_limite': fechaLimite.toIso8601String().split('T').first,
        if (descripcion != null) 'p_descripcion': descripcion,
        if (asignadoA != null) 'p_asignado_a': asignadoA,
      },
    );
    ref.invalidateSelf();
    ref.invalidate(chatterActividadesProvider(arg));
    ref.invalidate(chatterActividadesPendientesProvider(arg));
  }

  Future<void> completarActividad(String actividadId, {String? resultado}) async {
    await Supabase.instance.client.rpc(
      'chatter_completar_actividad',
      params: {
        'p_actividad_id': actividadId,
        if (resultado != null) 'p_resultado': resultado,
      },
    );
    ref.invalidateSelf();
    ref.invalidate(chatterActividadesProvider(arg));
    ref.invalidate(chatterActividadesPendientesProvider(arg));
    // Invalidar mensajes porque completar genera un mensaje de actividad_completada
    ref.invalidate(chatterProvider(arg));
  }

  Future<List<ChatterActividad>> _fetch(ChatterRef arg) async {
    final rows = await Supabase.instance.client.rpc(
      'chatter_get_actividades',
      params: {
        'p_entidad_tipo': arg.entidadTipo,
        'p_entidad_id': arg.entidadId,
        'p_solo_pendientes': false,
      },
    );
    return (rows as List<dynamic>)
        .map((r) => ChatterActividad.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

final chatterActividadesNotifierProvider = AsyncNotifierProvider.family<
    ChatterActividadesNotifier,
    List<ChatterActividad>,
    ChatterRef>(
  ChatterActividadesNotifier.new,
);

// ---------------------------------------------------------------------------
// Conversaciones externas vinculadas a un registro
// ---------------------------------------------------------------------------

/// Modelo para una conversación externa (WhatsApp/Telegram/Email) vinculada
/// a un registro de negocio (factura, contacto, orden, etc.).
@immutable
class ComConversacionVinculada {
  final String id;

  /// 'whatsapp' | 'telegram' | 'email_smtp' | 'email_api'
  final String canal;

  /// Número E.164, email, o chat_id según el canal.
  final String destinatarioRef;
  final String? destinatarioNombre;
  final DateTime? ultimoMensajeEn;
  final bool activa;

  const ComConversacionVinculada({
    required this.id,
    required this.canal,
    required this.destinatarioRef,
    this.destinatarioNombre,
    this.ultimoMensajeEn,
    required this.activa,
  });

  factory ComConversacionVinculada.fromJson(Map<String, dynamic> json) =>
      ComConversacionVinculada(
        id: json['id'] as String,
        canal: json['canal'] as String,
        destinatarioRef: json['destinatario_ref'] as String,
        destinatarioNombre: json['destinatario_nombre'] as String?,
        ultimoMensajeEn: json['ultimo_mensaje_en'] == null
            ? null
            : DateTime.parse(json['ultimo_mensaje_en'] as String),
        activa: json['activa'] as bool? ?? true,
      );

  /// Label legible para el canal.
  String get canalLabel => switch (canal) {
        'whatsapp' => 'WhatsApp',
        'telegram' => 'Telegram',
        'email_smtp' => 'Email SMTP',
        'email_api' => 'Email',
        _ => canal,
      };

  /// Nombre de display: usa `destinatarioNombre` si está disponible,
  /// fallback al `destinatarioRef`.
  String get displayName =>
      destinatarioNombre?.isNotEmpty == true ? destinatarioNombre! : destinatarioRef;
}

/// Provider: lista de conversaciones externas vinculadas a un registro.
///
/// Uso: `ref.watch(comConversacionesVinculadasProvider((entidadTipo: 'facturas', entidadId: id)))`
final comConversacionesVinculadasProvider =
    FutureProvider.family<List<ComConversacionVinculada>, ChatterRef>(
  (ref, arg) async {
    final data = await Supabase.instance.client.rpc(
      'com_get_conversaciones_entidad',
      params: {
        'p_entidad_tipo': arg.entidadTipo,
        'p_entidad_id': arg.entidadId,
      },
    );
    return (data as List<dynamic>)
        .map((e) => ComConversacionVinculada.fromJson(e as Map<String, dynamic>))
        .toList();
  },
);

// ---------------------------------------------------------------------------
// Notifier para vincular / desvincular conversaciones
// ---------------------------------------------------------------------------

class ComVincularNotifier extends FamilyAsyncNotifier<void, ChatterRef> {
  @override
  Future<void> build(ChatterRef arg) async {}

  /// Vincula la conversación al registro identificado por [arg].
  Future<void> vincular(String conversacionId) async {
    await Supabase.instance.client.rpc('com_vincular_conversacion', params: {
      'p_conversacion_id': conversacionId,
      'p_entidad_tipo': arg.entidadTipo,
      'p_entidad_id': arg.entidadId,
    });
    // Refrescar: lista vinculada + mensajes del chatter (puede incluir el log)
    ref.invalidate(comConversacionesVinculadasProvider(arg));
    ref.invalidate(chatterProvider(arg));
  }

  /// Desvincula la conversación del registro al que está asociada.
  Future<void> desvincular(String conversacionId) async {
    await Supabase.instance.client.rpc('com_desvincular_conversacion', params: {
      'p_conversacion_id': conversacionId,
    });
    ref.invalidate(comConversacionesVinculadasProvider(arg));
    ref.invalidate(chatterProvider(arg));
  }

  /// Busca la conversación más reciente vinculable con una entidad de negocio
  /// y la asocia al registro identificado por [arg].
  ///
  /// Se usa desde el `ChatterVincularDialog` cuando el flujo es:
  /// "el usuario elige un registro de negocio → vincular al chatter actual".
  ///
  /// Llama a la RPC `com_vincular_entidad_a_conversacion` que ubica o crea
  /// la vinculación entre la entidad destino y las conversaciones existentes.
  /// Invalida los providers tras una vinculación ya realizada externamente
  /// (p.ej. desde ChatterVincularDialog o _VincularConversacionDialog).
  void vincularConEntidad(String entidadTipo, String entidadId) {
    ref.invalidate(comConversacionesVinculadasProvider(arg));
    ref.invalidate(chatterProvider(arg));
  }
}

final comVincularProvider =
    AsyncNotifierProvider.family<ComVincularNotifier, void, ChatterRef>(
  ComVincularNotifier.new,
);

// ---------------------------------------------------------------------------
// chatterBuscarEntidadProvider — búsqueda de entidades para vincular
// ---------------------------------------------------------------------------

/// Busca entidades de negocio (contactos, facturas, etc.) para el diálogo de
/// vinculación del chatter.
///
/// Uso:
/// ```dart
/// final data = await ref.read(
///   chatterBuscarEntidadProvider((tipo: 'contactos', busqueda: q)).future,
/// );
/// ```
final chatterBuscarEntidadProvider = FutureProvider.autoDispose
    .family<List<({String id, String etiqueta, String? secundario})>,
        ({String tipo, String? busqueda})>(
  (ref, params) async {
    if ((params.busqueda?.length ?? 0) < 2 && params.busqueda != null) {
      return const [];
    }
    final data = await Supabase.instance.client.rpc(
      'chatter_buscar_entidad',
      params: {
        'p_tipo': params.tipo,
        'p_busqueda': params.busqueda?.trim().isEmpty == true
            ? null
            : params.busqueda?.trim(),
        'p_limit': 20,
      },
    ) as List;
    return data
        .map((e) {
          final m = e as Map<String, dynamic>;
          return (
            id: m['entidad_id'] as String,
            etiqueta: m['etiqueta'] as String? ?? m['entidad_id'] as String,
            secundario: m['secundario'] as String?,
          );
        })
        .toList();
  },
);

// ---------------------------------------------------------------------------
// Búsqueda de conversaciones no vinculadas
// ---------------------------------------------------------------------------

/// Busca conversaciones de com_conversaciones que no tienen entidad vinculada
/// y cuyo destinatario_ref coincide con [query].
///
/// Uso desde _VincularConversacionDialog.
Future<List<Map<String, dynamic>>> buscarConversacionesNoVinculadas(
  String query,
) async {
  final rows = await Supabase.instance.client
      .from('com_conversaciones')
      .select('id, canal, destinatario_ref, destinatario_nombre, entidad_id')
      .isFilter('entidad_id', null)
      .ilike('destinatario_ref', '%$query%')
      .limit(20);

  return (rows as List<dynamic>)
      .map((r) => r as Map<String, dynamic>)
      .toList();
}

// ---------------------------------------------------------------------------
// comCuentasPorTipoProvider — cuentas de comunicación filtradas por tipo
// ---------------------------------------------------------------------------

/// Retorna las cuentas de comunicación activas filtradas por tipo de canal.
/// [tipos] puede ser null para cargar todos los tipos o una lista de tipos
/// como ['whatsapp', 'telegram'].
///
/// Uso:
/// ```dart
/// final cuentas = ref.watch(
///   comCuentasPorTipoProvider(['whatsapp', 'telegram']),
/// );
/// ```
final comCuentasPorTipoProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, List<String>?>(
  (ref, tipos) async {
    final query = Supabase.instance.client
        .from('com_cuentas')
        .select('id, nombre, tipo')
        .eq('activo', true);

    final rows = tipos != null && tipos.isNotEmpty
        ? await query.inFilter('tipo', tipos)
        : await query;

    return (rows as List).cast<Map<String, dynamic>>();
  },
);

// ---------------------------------------------------------------------------
// ComSendDesdeEntidadNotifier — envío de mensaje externo desde una entidad
// ---------------------------------------------------------------------------

/// Notifier para enviar un mensaje externo (WhatsApp/Email/Telegram)
/// vinculado a una entidad de negocio.
///
/// Uso:
/// ```dart
/// await ref.read(comSendDesdeEntidadProvider.notifier).enviar(
///   entidadTipo: 'facturas',
///   entidadId: id,
///   canal: 'whatsapp',
///   cuentaId: cid,
///   destinatarioRef: '+593...',
///   cuerpo: 'Hola...',
/// );
/// ```
class ComSendDesdeEntidadNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> enviar({
    required String entidadTipo,
    required String entidadId,
    required String canal,
    required String cuentaId,
    required String destinatarioRef,
    required String cuerpo,
    String? destinatarioNombre,
    String? contactoId,
  }) async {
    await Supabase.instance.client.rpc(
      'com_send_desde_entidad',
      params: {
        'p_entidad_tipo': entidadTipo,
        'p_entidad_id': entidadId,
        'p_canal': canal,
        'p_cuenta_id': cuentaId,
        'p_destinatario_ref': destinatarioRef,
        'p_cuerpo': cuerpo,
        if (destinatarioNombre?.isNotEmpty == true)
          'p_destinatario_nombre': destinatarioNombre,
        if (contactoId != null) 'p_contacto_id': contactoId,
      },
    );
  }
}

final comSendDesdeEntidadProvider =
    AsyncNotifierProvider<ComSendDesdeEntidadNotifier, void>(
        ComSendDesdeEntidadNotifier.new);

// ---------------------------------------------------------------------------
// ComVincularConversacionNotifier — vincula conversación a entidad de negocio
// ---------------------------------------------------------------------------

/// Notifier para vincular una conversación existente a un registro de negocio.
///
/// Uso:
/// ```dart
/// await ref.read(comVincularConversacionProvider.notifier).vincular(
///   conversacionId: conv.id,
///   entidadTipo: 'contactos',
///   entidadId: contactoId,
/// );
/// ```
class ComVincularConversacionNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> vincular({
    required String conversacionId,
    required String entidadTipo,
    required String entidadId,
  }) async {
    await Supabase.instance.client.rpc(
      'com_vincular_conversacion',
      params: {
        'p_conversacion_id': conversacionId,
        'p_entidad_tipo': entidadTipo,
        'p_entidad_id': entidadId,
      },
    );
  }
}

final comVincularConversacionProvider =
    AsyncNotifierProvider<ComVincularConversacionNotifier, void>(
        ComVincularConversacionNotifier.new);
