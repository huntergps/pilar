import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'com_conversaciones'),
)
class ComConversacion extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  /// empresa_id: solo en Supabase, no en SQLite (RLS filtra por empresa).
  @Supabase(name: 'empresa_id')
  @Sqlite(ignore: true)
  final String? empresaId;

  @Supabase(name: 'cuenta_id')
  final String cuentaId;

  /// 'whatsapp' | 'email_api' | 'email_smtp' | 'telegram'
  final String canal;

  /// Número E.164 (WA), dirección email, o chat_id (Telegram).
  @Supabase(name: 'destinatario_ref')
  final String destinatarioRef;

  @Supabase(name: 'destinatario_nombre')
  final String? destinatarioNombre;

  /// contacto_id: soft ref, solo Supabase.
  @Supabase(name: 'contacto_id')
  @Sqlite(ignore: true)
  final String? contactoId;

  @Supabase(name: 'ultimo_mensaje_en')
  final DateTime? ultimoMensajeEn;

  /// Fin de la ventana de 24h de WhatsApp. NULL para email/Telegram.
  @Supabase(name: 'valida_hasta')
  final DateTime? validaHasta;

  @Sqlite(index: true)
  final bool activa;

  /// meta_json: JSONB — solo Supabase, no cacheado en SQLite.
  @Supabase(name: 'meta_json')
  @Sqlite(ignore: true)
  final Map<String, dynamic>? metaJson;

  /// entidad_tipo: soft ref, solo Supabase.
  @Supabase(name: 'entidad_tipo')
  @Sqlite(ignore: true)
  final String? entidadTipo;

  /// entidad_id: soft ref, solo Supabase.
  @Supabase(name: 'entidad_id')
  @Sqlite(ignore: true)
  final String? entidadId;

  @Supabase(name: 'creado_en')
  final DateTime? creadoEn;

  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  ComConversacion({
    required this.id,
    this.empresaId,
    required this.cuentaId,
    required this.canal,
    required this.destinatarioRef,
    this.destinatarioNombre,
    this.contactoId,
    this.ultimoMensajeEn,
    this.validaHasta,
    required this.activa,
    this.metaJson,
    this.entidadTipo,
    this.entidadId,
    this.creadoEn,
    this.version = 1,
  });

  /// true si la ventana WA de 24h está activa (siempre true para email/Telegram).
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  bool get ventanaWaActiva {
    if (canal != 'whatsapp') return true;
    if (validaHasta == null) return false;
    return validaHasta!.isAfter(DateTime.now());
  }

  /// Nombre de display: usa destinatarioNombre si está disponible.
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  String get displayName =>
      (destinatarioNombre?.isNotEmpty == true) ? destinatarioNombre! : destinatarioRef;

  /// JSONB deserializado (null cuando no está disponible — e.g., offline).
  @Supabase(ignore: true)
  @Sqlite(ignore: true)
  Map<String, dynamic> get metaParsed => metaJson ?? const {};

  factory ComConversacion.fromJson(Map<String, dynamic> json) {
    return ComConversacion(
      id: json['id'] as String,
      empresaId: json['empresa_id'] as String?,
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
      metaJson: json['meta_json'] as Map<String, dynamic>?,
      creadoEn: json['creado_en'] != null
          ? DateTime.parse(json['creado_en'] as String)
          : null,
      entidadTipo: json['entidad_tipo'] as String?,
      entidadId: json['entidad_id'] as String?,
      version: json['version'] as int? ?? 1,
    );
  }
}
