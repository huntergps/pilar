import 'dart:convert';

import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'chatter_mensajes'),
)
class ChatterMensaje extends OfflineFirstWithSupabaseModel {
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

  /// 'comentario' | 'log_sistema' | 'email_entrante' | 'actividad_completada'
  final String tipo;

  /// 'discusion' | 'nota_interna' | 'cambio_campo' | 'cambio_estado'
  /// | 'actividad_completada' | 'email_entrante'
  final String subtype;

  @Supabase(name: 'es_interno')
  final bool esInterno;

  final String? cuerpo;

  @Supabase(name: 'autor_id')
  final String? autorId;

  @Supabase(name: 'autor_nombre')
  final String autorNombre;

  @Supabase(name: 'autor_avatar')
  final String? autorAvatar;

  /// adjuntos_ids: UUID[] — solo disponible via fromJson (RPC online).
  /// Siempre '[]' cuando se lee de SQLite (offline).
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  final String adjuntosIdsJson;

  /// metadatos_json: JSONB — solo disponible via fromJson (RPC online).
  /// Siempre '{}' cuando se lee de SQLite (offline).
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  final String metadatosJson;

  @Supabase(name: 'creado_en')
  final DateTime? creadoEn;

  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  ChatterMensaje({
    required this.id,
    this.empresaId,
    required this.entidadTipo,
    required this.entidadId,
    required this.tipo,
    required this.subtype,
    required this.esInterno,
    this.cuerpo,
    this.autorId,
    required this.autorNombre,
    this.autorAvatar,
    this.adjuntosIdsJson = '[]',
    this.metadatosJson = '{}',
    this.creadoEn,
    this.version = 1,
  });

  // ---------------------------------------------------------------------------
  // Accessors para campos JSON (disponibles online, vacíos offline)
  // ---------------------------------------------------------------------------

  /// UUIDs de adjuntos en tabla `adjuntos`.
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  List<String> get adjuntosIds {
    try {
      final l = jsonDecode(adjuntosIdsJson) as List? ?? [];
      return l.cast<String>();
    } catch (_) {
      return const [];
    }
  }

  /// metadatos deserializados: `{ campo: { antes: '...', despues: '...' } }`
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  Map<String, dynamic> get metadatos {
    try {
      return Map<String, dynamic>.from(jsonDecode(metadatosJson) as Map? ?? {});
    } catch (_) {
      return const {};
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers de tipo
  // ---------------------------------------------------------------------------

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get esLog => tipo == 'log_sistema';

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get esComentario => tipo == 'comentario';

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get esEmail => tipo == 'email_entrante';

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get esActividad => tipo == 'actividad_completada';

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get esNotaInterna => esComentario && esInterno;

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get tieneAdjuntos => adjuntosIds.isNotEmpty;

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get tieneCamposTrackeados =>
      metadatos.isNotEmpty && tipo == 'log_sistema';

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  List<({String campo, String? antes, String? despues})> get cambiosCampos {
    if (!tieneCamposTrackeados) return const [];
    return metadatos.entries.map((e) {
      final v = e.value as Map<String, dynamic>;
      return (
        campo: e.key,
        antes: v['antes']?.toString(),
        despues: v['despues']?.toString(),
      );
    }).toList();
  }

  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  String get autorInicial =>
      autorNombre.isNotEmpty ? autorNombre[0].toUpperCase() : '?';

  String tiempoRelativo([DateTime? ahora]) {
    final now = ahora ?? DateTime.now();
    final ts = creadoEn ?? DateTime.now();
    final diff = now.difference(ts.toLocal());
    if (diff.inSeconds < 60) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 30) return 'hace ${diff.inDays} d';
    return 'hace ${(diff.inDays / 30).floor()} mes';
  }

  // ---------------------------------------------------------------------------
  // fromJson (para web RPC path)
  // ---------------------------------------------------------------------------

  factory ChatterMensaje.fromJson(Map<String, dynamic> json) {
    // adjuntos_ids puede venir como List<dynamic> o null
    final rawIds = json['adjuntos_ids'];
    String idsJson = '[]';
    if (rawIds is List) {
      idsJson = jsonEncode(rawIds.map((e) => e.toString()).toList());
    }

    // metadatos_json puede venir como Map o null
    final rawMeta = json['metadatos_json'];
    String metaStr = '{}';
    if (rawMeta is Map) {
      metaStr = jsonEncode(rawMeta);
    }

    return ChatterMensaje(
      id: json['id'] as String,
      empresaId: json['empresa_id'] as String?,
      entidadTipo: json['entidad_tipo'] as String? ?? '',
      entidadId: json['entidad_id'] as String? ?? '',
      tipo: json['tipo'] as String,
      subtype: json['subtype'] as String? ?? 'discusion',
      esInterno: json['es_interno'] as bool? ?? false,
      cuerpo: json['cuerpo'] as String?,
      autorId: json['autor_id'] as String?,
      autorNombre: json['autor_nombre'] as String? ?? 'Sistema',
      autorAvatar: json['autor_avatar'] as String?,
      adjuntosIdsJson: idsJson,
      metadatosJson: metaStr,
      creadoEn: json['creado_en'] != null
          ? DateTime.parse(json['creado_en'] as String)
          : null,
      version: json['version'] as int? ?? 1,
    );
  }
}
