/// Modelo para la tabla `com_conversaciones`.
///
/// Representa un hilo de conversación entre la empresa y un destinatario
/// externo (cliente de WhatsApp, email, Telegram).
class ComConversacion {
  final String id;
  final String empresaId;
  final String cuentaId;

  /// 'whatsapp' | 'email_api' | 'email_smtp' | 'telegram'
  final String canal;

  /// Número E.164 (WA), dirección email, o chat_id (Telegram).
  final String destinatarioRef;
  final String? destinatarioNombre;
  final String? contactoId;

  final DateTime? ultimoMensajeEn;

  /// Fin de la ventana de 24h de WhatsApp. NULL para email/Telegram.
  final DateTime? validaHasta;

  final bool activa;
  final Map<String, dynamic> metaJson;
  final DateTime creadoEn;

  /// Tipo de entidad de negocio vinculada (ej: 'facturas', 'contactos'). Nullable.
  final String? entidadTipo;

  /// UUID del registro de negocio vinculado. Nullable.
  final String? entidadId;

  const ComConversacion({
    required this.id,
    required this.empresaId,
    required this.cuentaId,
    required this.canal,
    required this.destinatarioRef,
    this.destinatarioNombre,
    this.contactoId,
    this.ultimoMensajeEn,
    this.validaHasta,
    required this.activa,
    required this.metaJson,
    required this.creadoEn,
    this.entidadTipo,
    this.entidadId,
  });

  /// `true` si la ventana de 24h de WhatsApp está activa (se puede enviar texto libre).
  /// Siempre `true` para email y Telegram (sin restricción de ventana).
  bool get ventanaWaActiva {
    if (canal != 'whatsapp') return true;
    if (validaHasta == null) return false;
    return validaHasta!.isAfter(DateTime.now());
  }

  /// Nombre de display: usa `destinatarioNombre` si está disponible,
  /// fallback al `destinatarioRef` (número o email).
  String get displayName => destinatarioNombre?.isNotEmpty == true
      ? destinatarioNombre!
      : destinatarioRef;

  factory ComConversacion.fromJson(Map<String, dynamic> json) {
    return ComConversacion(
      id: json['id'] as String,
      // empresa_id is not returned by com_get_conversaciones RPC; default to empty.
      empresaId: json['empresa_id'] as String? ?? '',
      cuentaId: json['cuenta_id'] as String,
      canal: json['canal'] as String,
      destinatarioRef: json['destinatario_ref'] as String,
      destinatarioNombre: json['destinatario_nombre'] as String?,
      contactoId: json['contacto_id'] as String?,
      ultimoMensajeEn: json['ultimo_mensaje_en'] == null
          ? null
          : DateTime.parse(json['ultimo_mensaje_en'] as String),
      validaHasta: json['valida_hasta'] == null
          ? null
          : DateTime.parse(json['valida_hasta'] as String),
      activa: json['activa'] as bool? ?? true,
      // meta_json is not returned by com_get_conversaciones RPC; default to empty.
      metaJson: (json['meta_json'] as Map<String, dynamic>?) ?? {},
      // creado_en is not returned by com_get_conversaciones RPC; default to epoch.
      creadoEn: json['creado_en'] != null
          ? DateTime.parse(json['creado_en'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
      entidadTipo: json['entidad_tipo'] as String?,
      entidadId: json['entidad_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'empresa_id': empresaId,
        'cuenta_id': cuentaId,
        'canal': canal,
        'destinatario_ref': destinatarioRef,
        'destinatario_nombre': destinatarioNombre,
        'contacto_id': contactoId,
        'ultimo_mensaje_en': ultimoMensajeEn?.toIso8601String(),
        'valida_hasta': validaHasta?.toIso8601String(),
        'activa': activa,
        'meta_json': metaJson,
        'creado_en': creadoEn.toIso8601String(),
        'entidad_tipo': entidadTipo,
        'entidad_id': entidadId,
      };
}
