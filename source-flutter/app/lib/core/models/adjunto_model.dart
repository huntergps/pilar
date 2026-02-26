// Modelo de adjunto (Foundation layer).
// Polimórfico: cualquier entidad (factura, contacto, empresa, etc.) puede tener archivos.

import 'package:flutter/foundation.dart';

@immutable
class AdjuntoItem {
  final String id;
  final String empresaId;
  final String entidadTipo;  // 'factura', 'contacto', 'empresa', etc.
  final String entidadId;
  final String nombre;         // nombre para mostrar (editable)
  final String nombreOriginal; // nombre original del archivo
  final String mimeType;
  final int tamanioBytes;
  final String storagePath;    // path dentro del bucket "adjuntos"
  final String storageBucket;
  final String? descripcion;
  final bool esPublico;
  final String? subidoPor;
  final DateTime createdAt;
  final List<String> tags;  // etiquetas libres para clasificación
  final int version;         // para versionado futuro

  const AdjuntoItem({
    required this.id,
    required this.empresaId,
    required this.entidadTipo,
    required this.entidadId,
    required this.nombre,
    required this.nombreOriginal,
    required this.mimeType,
    required this.tamanioBytes,
    required this.storagePath,
    required this.storageBucket,
    this.descripcion,
    required this.esPublico,
    this.subidoPor,
    required this.createdAt,
    this.tags = const [],
    this.version = 1,
  });

  factory AdjuntoItem.fromJson(Map<String, dynamic> json) => AdjuntoItem(
        id: json['id'] as String,
        empresaId: json['empresa_id'] as String,
        entidadTipo: json['entidad_tipo'] as String,
        entidadId: json['entidad_id'] as String,
        nombre: json['nombre'] as String,
        nombreOriginal: json['nombre_original'] as String,
        mimeType: json['mime_type'] as String,
        tamanioBytes: (json['tamanio_bytes'] as num).toInt(),
        storagePath: json['storage_path'] as String,
        storageBucket: (json['storage_bucket'] as String?) ?? 'adjuntos',
        descripcion: json['descripcion'] as String?,
        esPublico: (json['es_publico'] as bool?) ?? false,
        subidoPor: json['subido_por'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        tags: (json['tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        version: (json['version'] as num?)?.toInt() ?? 1,
      );

  // ---------------------------------------------------------------------------
  // Helpers visuales
  // ---------------------------------------------------------------------------

  /// Ícono según tipo MIME para usar con fluent_ui / FluentIcons.
  String get iconCategory {
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType == 'application/pdf') return 'pdf';
    if (mimeType.contains('word') || mimeType.contains('.document')) return 'word';
    if (mimeType.contains('excel') || mimeType.contains('.sheet')) return 'excel';
    if (mimeType.contains('powerpoint') || mimeType.contains('.presentation')) return 'ppt';
    if (mimeType == 'text/csv') return 'csv';
    if (mimeType == 'application/zip') return 'zip';
    if (mimeType.contains('xml')) return 'xml';
    return 'file';
  }

  /// Tamaño formateado: "1.4 MB", "320 KB", etc.
  String get tamanioLabel {
    if (tamanioBytes < 1024) return '$tamanioBytes B';
    if (tamanioBytes < 1024 * 1024) {
      return '${(tamanioBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(tamanioBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// Extensión del archivo en mayúsculas: "PDF", "DOCX", etc.
  String get extension => nombreOriginal.split('.').last.toUpperCase();
}
