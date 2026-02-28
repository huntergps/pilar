// Modelo de actividad del Chatter (Foundation layer).
//
// Representa tareas, llamadas, emails, reuniones y documentos pendientes
// o completados asociados a un registro de cualquier entidad.

import 'package:flutter/foundation.dart';

@immutable
class ChatterActividad {
  final String id;
  final String entidadTipo;
  final String entidadId;

  /// 'tarea' | 'llamada' | 'email' | 'reunion' | 'documento'
  final String tipo;

  final String titulo;
  final String? descripcion;
  final DateTime fechaLimite;

  /// UUID del usuario asignado (puede ser null si no está asignado)
  final String? asignadoA;

  /// null = pendiente; con valor = completada
  final DateTime? completadoEn;
  final String? resultado;
  final String? creadoPor;
  final DateTime creadoEn;

  const ChatterActividad({
    required this.id,
    required this.entidadTipo,
    required this.entidadId,
    required this.tipo,
    required this.titulo,
    this.descripcion,
    required this.fechaLimite,
    this.asignadoA,
    this.completadoEn,
    this.resultado,
    this.creadoPor,
    required this.creadoEn,
  });

  factory ChatterActividad.fromJson(Map<String, dynamic> json) =>
      ChatterActividad(
        id: json['id'] as String,
        entidadTipo: json['entidad_tipo'] as String,
        entidadId: json['entidad_id'] as String,
        tipo: json['tipo'] as String,
        titulo: json['titulo'] as String,
        descripcion: json['descripcion'] as String?,
        fechaLimite: DateTime.parse(json['fecha_limite'] as String),
        asignadoA: json['asignado_a'] as String?,
        completadoEn: json['completado_en'] != null
            ? DateTime.parse(json['completado_en'] as String)
            : null,
        resultado: json['resultado'] as String?,
        creadoPor: json['creado_por'] as String?,
        creadoEn: DateTime.parse(json['creado_en'] as String),
      );

  // ---------------------------------------------------------------------------
  // Helpers de estado
  // ---------------------------------------------------------------------------

  bool get esPendiente => completadoEn == null;
  bool get estaCompletada => completadoEn != null;

  bool get esVencida {
    if (!esPendiente) return false;
    final hoy = DateTime.now();
    final limite = DateTime(
      fechaLimite.year,
      fechaLimite.month,
      fechaLimite.day,
      23,
      59,
      59,
    );
    return hoy.isAfter(limite);
  }

  bool get esHoy {
    if (!esPendiente) return false;
    final hoy = DateTime.now();
    return fechaLimite.year == hoy.year &&
        fechaLimite.month == hoy.month &&
        fechaLimite.day == hoy.day;
  }

  /// 'vencida' | 'hoy' | 'planificada' | 'completada'
  String get estado {
    if (estaCompletada) return 'completada';
    if (esVencida) return 'vencida';
    if (esHoy) return 'hoy';
    return 'planificada';
  }

  // ---------------------------------------------------------------------------
  // Helpers de presentación
  // ---------------------------------------------------------------------------

  /// Etiqueta legible para la fecha límite.
  String get fechaLimiteLabel {
    if (esHoy) return 'Hoy';
    if (esVencida) {
      final diff = DateTime.now().difference(fechaLimite);
      return 'Venció hace ${diff.inDays} d';
    }
    final diff = fechaLimite.difference(DateTime.now());
    if (diff.inDays == 1) return 'Mañana';
    if (diff.inDays < 7) return 'En ${diff.inDays} días';
    return '${fechaLimite.day.toString().padLeft(2, '0')}/'
        '${fechaLimite.month.toString().padLeft(2, '0')}/'
        '${fechaLimite.year}';
  }
}
