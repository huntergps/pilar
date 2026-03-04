import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'modulos_empresa'),
)
class ModuloEmpresa extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  @Sqlite(index: true)
  final String empresaId;
  final String moduloId;
  final bool habilitado;

  /// Versión del registro — bloqueo optimista.
  /// Se incrementa en la BD con cada UPDATE. Brick lo sincroniza en SQLite.
  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  ModuloEmpresa({
    required this.id,
    required this.empresaId,
    required this.moduloId,
    required this.habilitado,
    this.version = 1,
  });
}
