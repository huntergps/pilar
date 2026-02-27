/// Resultado de la RPC `com_get_email_threads`.
///
/// Representa un hilo de conversación email con metadatos del último mensaje,
/// listo para mostrar en la bandeja estilo Gmail.
class EmailThread {
  final String conversacionId;
  final String cuentaId;
  final String canal;

  /// Nombre legible del contacto (fallback a email si sin nombre).
  final String deNombre;

  /// Dirección email del contacto.
  final String deRef;

  final String asunto;
  final String preview;
  final DateTime? fecha;

  /// True si el último mensaje ya fue leído o es outbound.
  final bool esLeido;

  final int totalMensajes;
  final String? estadoUltimo;
  final bool tieneAdjuntos;

  const EmailThread({
    required this.conversacionId,
    required this.cuentaId,
    required this.canal,
    required this.deNombre,
    required this.deRef,
    required this.asunto,
    required this.preview,
    required this.fecha,
    required this.esLeido,
    required this.totalMensajes,
    required this.estadoUltimo,
    required this.tieneAdjuntos,
  });

  factory EmailThread.fromJson(Map<String, dynamic> j) {
    return EmailThread(
      conversacionId: j['conversacion_id'] as String,
      cuentaId: j['cuenta_id'] as String,
      canal: j['canal'] as String,
      deNombre: j['de_nombre'] as String? ?? j['de_ref'] as String,
      deRef: j['de_ref'] as String,
      asunto: j['asunto'] as String? ?? '(Sin asunto)',
      preview: j['preview'] as String? ?? '',
      fecha: j['fecha'] == null
          ? null
          : DateTime.parse(j['fecha'] as String).toLocal(),
      esLeido: j['es_leido'] as bool? ?? false,
      totalMensajes: (j['total_mensajes'] as num?)?.toInt() ?? 0,
      estadoUltimo: j['estado_ultimo'] as String?,
      tieneAdjuntos: j['tiene_adjuntos'] as bool? ?? false,
    );
  }
}
