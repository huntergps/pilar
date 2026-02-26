import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'usuarios_empresa'),
)
class UsuarioEmpresaPerfil extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  final String usuarioId;
  final String empresaId;
  final bool activo;
  final String? nombreDisplay;
  final String? avatarUrl;
  final String? telefono;
  final String? emailContacto;
  final String? zonaHoraria;

  UsuarioEmpresaPerfil({
    required this.id,
    required this.usuarioId,
    required this.empresaId,
    required this.activo,
    this.nombreDisplay,
    this.avatarUrl,
    this.telefono,
    this.emailContacto,
    this.zonaHoraria,
  });
}
