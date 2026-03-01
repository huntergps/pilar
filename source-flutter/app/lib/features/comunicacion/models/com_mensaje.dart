import 'dart:convert';

/// Un adjunto de media en un mensaje (foto, video, audio, documento, sticker).
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
        tipo:     j['tipo'] as String? ?? 'documento',
        url:      j['url']  as String? ?? '',
        nombre:   j['nombre'] as String? ?? 'archivo',
        mimeType: j['mime_type'] as String? ?? 'application/octet-stream',
        tamano:   (j['tamano'] as num?)?.toInt() ?? 0,
      );

  bool get esImagen  => tipo == 'imagen'  || tipo == 'sticker';
  bool get esVideo   => tipo == 'video'   || tipo == 'video_nota';
  bool get esAudio   => tipo == 'audio'   || tipo == 'voz';
  bool get esDocumento => tipo == 'documento';
}

/// Modelo para la tabla `com_mensajes`.
///
/// Representa un mensaje individual en una conversación multicanal
/// (WhatsApp, Email API/SMTP, Telegram) o una notificación saliente.
class ComMensaje {
  final String id;
  final String empresaId;
  final String cuentaId;
  final String? conversacionId;

  /// 'outbound' | 'inbound'
  final String tipo;

  /// 'whatsapp' | 'email_api' | 'email_smtp' | 'telegram'
  final String canal;

  final String destinatarioRef;
  final String? cuerpo;
  final String? asunto;

  /// 'pendiente' | 'encolado' | 'enviado' | 'entregado' | 'leido'
  /// | 'recibido' | 'fallido' | 'rebotado' | 'cancelado'
  final String estado;

  /// ID del mensaje en la plataforma externa (ej. message_id de WhatsApp).
  final String? mensajeUid;

  /// ID del mensaje padre (para hilos/respuestas).
  final String? padreId;

  /// Tipo de entidad de negocio referenciada (ej. 'factura', 'cotizacion').
  final String? entidadTipo;

  /// ID de la entidad de negocio referenciada.
  final String? entidadId;

  /// Adjuntos de media (fotos, videos, audios, documentos).
  final List<ComAdjunto> adjuntos;

  final DateTime? enviadoEn;
  final DateTime? entregadoEn;
  final DateTime? leidoEn;
  final DateTime creadoEn;

  const ComMensaje({
    required this.id,
    required this.empresaId,
    required this.cuentaId,
    this.conversacionId,
    required this.tipo,
    required this.canal,
    required this.destinatarioRef,
    this.cuerpo,
    this.asunto,
    required this.estado,
    this.mensajeUid,
    this.padreId,
    this.entidadTipo,
    this.entidadId,
    this.adjuntos = const [],
    this.enviadoEn,
    this.entregadoEn,
    this.leidoEn,
    required this.creadoEn,
  });

  bool get esInbound  => tipo == 'inbound';
  bool get esOutbound => tipo == 'outbound';
  bool get esFallido  => estado == 'fallido' || estado == 'rebotado';
  bool get tieneMedia => adjuntos.isNotEmpty;

  factory ComMensaje.fromJson(Map<String, dynamic> json) {
    // adjuntos_json puede venir como String (de la SETOF) o List
    List<ComAdjunto> adjuntos = const [];
    final rawAdj = json['adjuntos_json'];
    if (rawAdj != null) {
      List<dynamic> lista;
      if (rawAdj is String) {
        lista = (jsonDecode(rawAdj) as List?)?.cast<dynamic>() ?? [];
      } else if (rawAdj is List) {
        lista = rawAdj;
      } else {
        lista = [];
      }
      adjuntos = lista
          .whereType<Map<String, dynamic>>()
          .map(ComAdjunto.fromJson)
          .toList();
    }

    return ComMensaje(
      id:              json['id'] as String,
      empresaId:       json['empresa_id'] as String,
      cuentaId:        json['cuenta_id'] as String,
      conversacionId:  json['conversacion_id'] as String?,
      tipo:            json['tipo'] as String,
      canal:           json['canal'] as String,
      destinatarioRef: json['destinatario_ref'] as String,
      cuerpo:          json['cuerpo'] as String?,
      asunto:          json['asunto'] as String?,
      estado:          json['estado'] as String? ?? 'pendiente',
      mensajeUid:      json['mensaje_uid'] as String?,
      padreId:         json['padre_id'] as String?,
      entidadTipo:     json['entidad_tipo'] as String?,
      entidadId:       json['entidad_id'] as String?,
      adjuntos:        adjuntos,
      enviadoEn:  json['enviado_en']   == null ? null : DateTime.parse(json['enviado_en']   as String),
      entregadoEn: json['entregado_en'] == null ? null : DateTime.parse(json['entregado_en'] as String),
      leidoEn:    json['leido_en']     == null ? null : DateTime.parse(json['leido_en']     as String),
      creadoEn:   DateTime.parse(json['creado_en'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'empresa_id': empresaId,
        'cuenta_id': cuentaId,
        'conversacion_id': conversacionId,
        'tipo': tipo,
        'canal': canal,
        'destinatario_ref': destinatarioRef,
        'cuerpo': cuerpo,
        'asunto': asunto,
        'estado': estado,
        'mensaje_uid': mensajeUid,
        'padre_id': padreId,
        'entidad_tipo': entidadTipo,
        'entidad_id': entidadId,
        'enviado_en':   enviadoEn?.toIso8601String(),
        'entregado_en': entregadoEn?.toIso8601String(),
        'leido_en':     leidoEn?.toIso8601String(),
        'creado_en':    creadoEn.toIso8601String(),
      };
}
