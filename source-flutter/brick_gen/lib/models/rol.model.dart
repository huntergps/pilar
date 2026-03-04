import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'roles'),
)
class Rol extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  /// empresa_id: NULL = rol global del sistema; UUID = rol empresa-específico.
  /// Solo Supabase, no SQLite — filtrar en Dart según contexto.
  @Supabase(name: 'empresa_id')
  @Sqlite(ignore: true)
  final String? empresaId;

  final String codigo;
  final String nombre;
  final String? descripcion;

  @Supabase(name: 'es_sistema')
  final bool esSistema;

  final bool activo;

  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  Rol({
    required this.id,
    this.empresaId,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.esSistema,
    required this.activo,
    this.version = 1,
  });
}
