import 'dart:convert';

import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'adjuntos'),
)
class Adjunto extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  /// empresa_id: solo Supabase, no SQLite (RLS filtra por empresa).
  @Supabase(name: 'empresa_id')
  @Sqlite(ignore: true)
  final String? empresaId;

  /// entidad_tipo: indexado para queries offline.
  @Supabase(name: 'entidad_tipo')
  @Sqlite(index: true)
  final String entidadTipo;

  /// entidad_id: indexado para queries offline.
  @Supabase(name: 'entidad_id')
  @Sqlite(index: true)
  final String entidadId;

  /// Nombre para mostrar (editable por el usuario).
  final String nombre;

  /// Nombre original del archivo al momento de subida.
  @Supabase(name: 'nombre_original')
  final String nombreOriginal;

  @Supabase(name: 'mime_type')
  final String mimeType;

  @Supabase(name: 'tamanio_bytes')
  final int tamanioBytes;

  @Supabase(name: 'storage_path')
  final String storagePath;

  @Supabase(name: 'storage_bucket')
  final String storageBucket;

  final String? descripcion;

  @Supabase(name: 'es_publico')
  final bool esPublico;

  @Supabase(name: 'subido_por')
  @Sqlite(ignore: true)
  final String? subidoPor;

  /// tags: TEXT[] — solo disponible via fromJson (RPC online).
  /// Siempre '[]' cuando se lee de SQLite (offline).
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  final String tagsJson;

  @Supabase(name: 'created_at')
  final DateTime? createdAt;

  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  Adjunto({
    required this.id,
    this.empresaId,
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
    this.tagsJson = '[]',
    this.createdAt,
    this.version = 1,
  });

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  /// Etiquetas libres. Vacías cuando offline.
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  List<String> get tags {
    try {
      final l = jsonDecode(tagsJson) as List? ?? [];
      return l.cast<String>();
    } catch (_) {
      return const [];
    }
  }

  /// Ícono según tipo MIME.
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
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
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  String get tamanioLabel {
    if (tamanioBytes < 1024) return '$tamanioBytes B';
    if (tamanioBytes < 1024 * 1024) {
      return '${(tamanioBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(tamanioBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// Extensión del archivo en mayúsculas: "PDF", "DOCX", etc.
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  String get extension => nombreOriginal.split('.').last.toUpperCase();

  // ---------------------------------------------------------------------------
  // fromJson (para web RPC path)
  // ---------------------------------------------------------------------------

  factory Adjunto.fromJson(Map<String, dynamic> json) {
    // tags puede venir como List<dynamic> o null
    final rawTags = json['tags'];
    String tagsStr = '[]';
    if (rawTags is List) {
      tagsStr = jsonEncode(rawTags.map((e) => e.toString()).toList());
    }

    return Adjunto(
      id: json['id'] as String,
      empresaId: json['empresa_id'] as String?,
      entidadTipo: json['entidad_tipo'] as String,
      entidadId: json['entidad_id'] as String,
      nombre: json['nombre'] as String,
      nombreOriginal: json['nombre_original'] as String,
      mimeType: json['mime_type'] as String,
      tamanioBytes: (json['tamanio_bytes'] as num).toInt(),
      storagePath: json['storage_path'] as String,
      storageBucket: json['storage_bucket'] as String? ?? 'adjuntos',
      descripcion: json['descripcion'] as String?,
      esPublico: json['es_publico'] as bool? ?? false,
      subidoPor: json['subido_por'] as String?,
      tagsJson: tagsStr,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Alias de compatibilidad: AdjuntoItem es el nombre histórico en la app.
/// Los widgets pueden seguir usando AdjuntoItem hasta que migren a Adjunto.
typedef AdjuntoItem = Adjunto;
