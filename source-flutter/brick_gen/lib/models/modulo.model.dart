import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'modulos'),
)
class Modulo extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  final String nombre;
  final String? descripcion;
  final String tipo;
  final String? icono;
  final int? orden;
  final bool activo;

  Modulo({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.tipo,
    this.icono,
    this.orden,
    this.activo = true,
  });
}
