import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'empresas'),
)
class Empresa extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  final String nombre;
  final String? nombreComercial;
  final String? ruc;
  final String? logoUrl;
  final String? colorPrimario;
  final String? colorSecundario;
  final String? estado;

  /// Versión del registro — bloqueo optimista.
  /// Se incrementa en la BD con cada UPDATE. Brick lo sincroniza en SQLite.
  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  Empresa({
    required this.id,
    required this.nombre,
    this.nombreComercial,
    this.ruc,
    this.logoUrl,
    this.colorPrimario,
    this.colorSecundario,
    this.estado,
    this.version = 1,
  });
}
