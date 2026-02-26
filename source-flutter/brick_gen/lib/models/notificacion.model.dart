import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'notificaciones_usuario'),
)
class Notificacion extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  final String empresaId;
  final String usuarioId;
  final String tipo;
  final String titulo;
  final String? cuerpo;
  final String? icono;
  final String? accionUrl;
  final bool leida;
  final DateTime? createdAt;

  Notificacion({
    required this.id,
    required this.empresaId,
    required this.usuarioId,
    required this.tipo,
    required this.titulo,
    this.cuerpo,
    this.icono,
    this.accionUrl,
    required this.leida,
    this.createdAt,
  });
}
