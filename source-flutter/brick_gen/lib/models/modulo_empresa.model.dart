import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'modulos_empresa'),
)
class ModuloEmpresa extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  final String empresaId;
  final String moduloId;
  final bool habilitado;

  ModuloEmpresa({
    required this.id,
    required this.empresaId,
    required this.moduloId,
    required this.habilitado,
  });
}
