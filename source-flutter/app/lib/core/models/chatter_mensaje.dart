// Modelo de mensaje del Chatter (Foundation layer).
//
// Polimórfico: cualquier entidad (factura, contacto, orden, etc.) puede tener
// un hilo de chatter con comentarios, logs de sistema, actividades y emails.

import 'package:flutter/foundation.dart';

@immutable
class ChatterMensaje {
  final String id;

  /// 'comentario' | 'log_sistema' | 'email_entrante' | 'actividad_completada'
  final String tipo;

  /// 'discusion' | 'nota_interna' | 'cambio_campo' | 'cambio_estado'
  /// | 'actividad_completada' | 'email_entrante'
  final String subtype;

  final bool esInterno;
  final String? cuerpo;
  final String? autorId;
  final String autorNombre;
  final String? autorAvatar;

  /// UUIDs de adjuntos en tabla `adjuntos`
  final List<String> adjuntosIds;

  /// Para log_sistema: `{ campo: { antes: '...', despues: '...' } }`
  final Map<String, dynamic> metadatosJson;

  final DateTime creadoEn;

  const ChatterMensaje({
    required this.id,
    required this.tipo,
    required this.subtype,
    required this.esInterno,
    this.cuerpo,
    this.autorId,
    required this.autorNombre,
    this.autorAvatar,
    required this.adjuntosIds,
    required this.metadatosJson,
    required this.creadoEn,
  });

  factory ChatterMensaje.fromJson(Map<String, dynamic> json) {
    // adjuntos_ids puede venir como List<dynamic> o como null
    final rawIds = json['adjuntos_ids'];
    final adjuntosIds = rawIds == null
        ? <String>[]
        : (rawIds as List<dynamic>).map((e) => e as String).toList();

    // metadatos_json puede venir como Map o como null
    final rawMeta = json['metadatos_json'];
    final metadatosJson = rawMeta == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(rawMeta as Map);

    return ChatterMensaje(
      id: json['id'] as String,
      tipo: json['tipo'] as String,
      subtype: (json['subtype'] as String?) ?? 'discusion',
      esInterno: (json['es_interno'] as bool?) ?? false,
      cuerpo: json['cuerpo'] as String?,
      autorId: json['autor_id'] as String?,
      autorNombre: (json['autor_nombre'] as String?) ?? 'Sistema',
      autorAvatar: json['autor_avatar'] as String?,
      adjuntosIds: adjuntosIds,
      metadatosJson: metadatosJson,
      creadoEn: DateTime.parse(json['creado_en'] as String),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers de tipo
  // ---------------------------------------------------------------------------

  bool get esLog => tipo == 'log_sistema';
  bool get esComentario => tipo == 'comentario';
  bool get esEmail => tipo == 'email_entrante';
  bool get esActividad => tipo == 'actividad_completada';
  bool get esNotaInterna => esComentario && esInterno;
  bool get tieneAdjuntos => adjuntosIds.isNotEmpty;

  /// true cuando es un log con mapa de cambios de campos.
  bool get tieneCamposTrackeados =>
      metadatosJson.isNotEmpty && tipo == 'log_sistema';

  // ---------------------------------------------------------------------------
  // Cambios de campo (para log_sistema con subtype cambio_campo)
  // ---------------------------------------------------------------------------

  /// Devuelve la lista de campos que cambiaron con sus valores anterior/nuevo.
  List<({String campo, String? antes, String? despues})> get cambiosCampos {
    if (!tieneCamposTrackeados) return const [];
    return metadatosJson.entries.map((e) {
      final v = e.value as Map<String, dynamic>;
      return (
        campo: e.key,
        antes: v['antes']?.toString(),
        despues: v['despues']?.toString(),
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Helpers de presentación
  // ---------------------------------------------------------------------------

  /// Inicial del nombre del autor para el avatar fallback.
  String get autorInicial =>
      autorNombre.isNotEmpty ? autorNombre[0].toUpperCase() : '?';

  /// Etiqueta de tiempo relativo simple (sin librerías externas).
  String tiempoRelativo([DateTime? ahora]) {
    final now = ahora ?? DateTime.now();
    final diff = now.difference(creadoEn.toLocal());
    if (diff.inSeconds < 60) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 30) return 'hace ${diff.inDays} d';
    return 'hace ${(diff.inDays / 30).floor()} mes';
  }
}
