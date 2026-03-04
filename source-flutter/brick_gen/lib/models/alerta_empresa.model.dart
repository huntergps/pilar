import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'alertas_empresa'),
)
class AlertaEmpresa extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  @Sqlite(index: true)
  final String empresaId;
  final String origenModulo;
  final String? codigoAlerta;
  final String severidad;
  final String titulo;
  final String? cuerpo;
  final String? accionUrl;
  @Sqlite(index: true)
  final String estado;
  final DateTime? createdAt;

  /// Versión del registro — bloqueo optimista.
  /// Se incrementa en la BD con cada UPDATE. Brick lo sincroniza en SQLite.
  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  AlertaEmpresa({
    required this.id,
    required this.empresaId,
    required this.origenModulo,
    this.codigoAlerta,
    required this.severidad,
    required this.titulo,
    this.cuerpo,
    this.accionUrl,
    required this.estado,
    this.createdAt,
    this.version = 1,
  });
}
