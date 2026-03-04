import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'chat_mensajes'),
)
class ChatMensaje extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  /// canal_id: indexado para queries offline por canal.
  @Supabase(name: 'canal_id')
  @Sqlite(index: true)
  final String canalId;

  @Supabase(name: 'usuario_id')
  final String usuarioId;

  final String? cuerpo;

  @Supabase(name: 'created_at')
  final DateTime? createdAt;

  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  ChatMensaje({
    required this.id,
    required this.canalId,
    required this.usuarioId,
    this.cuerpo,
    this.createdAt,
    this.version = 1,
  });
}
