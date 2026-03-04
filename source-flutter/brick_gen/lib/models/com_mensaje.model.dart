import 'dart:convert';

import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

// ---------------------------------------------------------------------------
// ComAdjunto — valor embebido en adjuntos_json (no es entidad Brick)
// ---------------------------------------------------------------------------

class ComAdjunto {
  final String tipo; // 'imagen'|'video'|'audio'|'voz'|'documento'|'sticker'|'video_nota'
  final String url;
  final String nombre;
  final String mimeType;
  final int tamano;

  const ComAdjunto({
    required this.tipo,
    required this.url,
    required this.nombre,
    required this.mimeType,
    required this.tamano,
  });

  factory ComAdjunto.fromJson(Map<String, dynamic> j) => ComAdjunto(
        tipo: j['tipo'] as String? ?? 'documento',
        url: j['url'] as String? ?? '',
        nombre: j['nombre'] as String? ?? 'archivo',
        mimeType: j['mime_type'] as String? ?? 'application/octet-stream',
        tamano: (j['tamano'] as num?)?.toInt() ?? 0,
      );

  bool get esImagen => tipo == 'imagen' || tipo == 'sticker';
  bool get esVideo => tipo == 'video' || tipo == 'video_nota';
  bool get esAudio => tipo == 'audio' || tipo == 'voz';
  bool get esDocumento => tipo == 'documento';
}

// ---------------------------------------------------------------------------
// ComMensaje — modelo Brick para com_mensajes
// ---------------------------------------------------------------------------

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'com_mensajes'),
)
class ComMensaje extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  /// empresa_id: solo Supabase, no SQLite (RLS filtra por empresa).
  @Supabase(name: 'empresa_id')
  @Sqlite(ignore: true)
  final String? empresaId;

  @Supabase(name: 'cuenta_id')
  final String cuentaId;

  /// conversacion_id: indexado para queries offline.
  @Supabase(name: 'conversacion_id')
  @Sqlite(index: true)
  final String? conversacionId;

  /// 'outbound' | 'inbound'
  final String tipo;

  /// 'whatsapp' | 'email_api' | 'email_smtp' | 'telegram'
  final String canal;

  @Supabase(name: 'destinatario_ref')
  final String destinatarioRef;

  @Supabase(name: 'destinatario_nombre')
  final String? destinatarioNombre;

  final String? asunto;
  final String? cuerpo;

  /// 'pendiente' | 'encolado' | 'enviado' | 'entregado' | 'leido'
  /// | 'recibido' | 'fallido' | 'rebotado' | 'cancelado'
  @Sqlite(index: true)
  final String estado;

  @Supabase(name: 'mensaje_uid')
  final String? mensajeUid;

  @Supabase(name: 'padre_id')
  @Sqlite(ignore: true)
  final String? padreId;

  @Supabase(name: 'entidad_tipo')
  @Sqlite(ignore: true)
  final String? entidadTipo;

  @Supabase(name: 'entidad_id')
  @Sqlite(ignore: true)
  final String? entidadId;

  /// adjuntos_json: JSONB complejo — solo disponible via fromJson (RPC online).
  /// Siempre '[]' cuando se lee de SQLite (offline).
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  final String adjuntosJson;

  @Supabase(name: 'enviado_en')
  final DateTime? enviadoEn;

  @Supabase(name: 'entregado_en')
  final DateTime? entregadoEn;

  @Supabase(name: 'leido_en')
  final DateTime? leidoEn;

  @Supabase(name: 'creado_en')
  final DateTime? creadoEn;

  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  ComMensaje({
    required this.id,
    this.empresaId,
    required this.cuentaId,
    this.conversacionId,
    required this.tipo,
    required this.canal,
    required this.destinatarioRef,
    this.destinatarioNombre,
    this.asunto,
    this.cuerpo,
    required this.estado,
    this.mensajeUid,
    this.padreId,
    this.entidadTipo,
    this.entidadId,
    this.adjuntosJson = '[]',
    this.enviadoEn,
    this.entregadoEn,
    this.leidoEn,
    this.creadoEn,
    this.version = 1,
  });

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get esInbound => tipo == 'inbound';

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get esOutbound => tipo == 'outbound';

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get esFallido => estado == 'fallido' || estado == 'rebotado';

  /// Adjuntos deserializados. Vacío cuando offline (no cacheado en SQLite).
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  List<ComAdjunto> get adjuntos {
    try {
      final lista = jsonDecode(adjuntosJson) as List? ?? [];
      return lista.whereType<Map<String, dynamic>>().map(ComAdjunto.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get tieneMedia => adjuntos.isNotEmpty;

  factory ComMensaje.fromJson(Map<String, dynamic> json) {
    // adjuntos_json puede venir como String (SETOF) o como List (tabla directa)
    final rawAdj = json['adjuntos_json'];
    String adjJson = '[]';
    if (rawAdj is String) {
      adjJson = rawAdj;
    } else if (rawAdj is List) {
      adjJson = jsonEncode(rawAdj);
    }

    return ComMensaje(
      id: json['id'] as String,
      empresaId: json['empresa_id'] as String?,
      cuentaId: json['cuenta_id'] as String,
      conversacionId: json['conversacion_id'] as String?,
      tipo: json['tipo'] as String,
      canal: json['canal'] as String,
      destinatarioRef: json['destinatario_ref'] as String,
      destinatarioNombre: json['destinatario_nombre'] as String?,
      asunto: json['asunto'] as String?,
      cuerpo: json['cuerpo'] as String?,
      estado: json['estado'] as String? ?? 'pendiente',
      mensajeUid: json['mensaje_uid'] as String?,
      padreId: json['padre_id'] as String?,
      entidadTipo: json['entidad_tipo'] as String?,
      entidadId: json['entidad_id'] as String?,
      adjuntosJson: adjJson,
      enviadoEn: json['enviado_en'] == null ? null : DateTime.parse(json['enviado_en'] as String),
      entregadoEn: json['entregado_en'] == null ? null : DateTime.parse(json['entregado_en'] as String),
      leidoEn: json['leido_en'] == null ? null : DateTime.parse(json['leido_en'] as String),
      creadoEn: json['creado_en'] != null ? DateTime.parse(json['creado_en'] as String) : null,
      version: json['version'] as int? ?? 1,
    );
  }
}
