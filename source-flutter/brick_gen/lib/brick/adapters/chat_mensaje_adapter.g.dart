// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<ChatMensaje> _$ChatMensajeFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ChatMensaje(
    id: data['id'] as String,
    canalId: data['canal_id'] as String,
    usuarioId: data['usuario_id'] as String,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    createdAt: data['created_at'] == null
        ? null
        : data['created_at'] == null
        ? null
        : DateTime.tryParse(data['created_at'] as String),
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$ChatMensajeToSupabase(
  ChatMensaje instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'canal_id': instance.canalId,
    'usuario_id': instance.usuarioId,
    'cuerpo': instance.cuerpo,
    'created_at': instance.createdAt?.toIso8601String(),
    'version': instance.version,
  };
}

Future<ChatMensaje> _$ChatMensajeFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ChatMensaje(
    id: data['id'] as String,
    canalId: data['canal_id'] as String,
    usuarioId: data['usuario_id'] as String,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    createdAt: data['created_at'] == null
        ? null
        : data['created_at'] == null
        ? null
        : DateTime.tryParse(data['created_at'] as String),
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ChatMensajeToSqlite(
  ChatMensaje instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'canal_id': instance.canalId,
    'usuario_id': instance.usuarioId,
    'cuerpo': instance.cuerpo,
    'created_at': instance.createdAt?.toIso8601String(),
    'version': instance.version,
  };
}

/// Construct a [ChatMensaje]
class ChatMensajeAdapter extends OfflineFirstWithSupabaseAdapter<ChatMensaje> {
  ChatMensajeAdapter();

  @override
  final supabaseTableName = 'chat_mensajes';
  @override
  final defaultToNull = true;
  @override
  final fieldsToSupabaseColumns = {
    'id': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'id',
    ),
    'canalId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'canal_id',
    ),
    'usuarioId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'usuario_id',
    ),
    'cuerpo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'cuerpo',
    ),
    'createdAt': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'created_at',
    ),
    'version': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'version',
    ),
  };
  @override
  final ignoreDuplicates = false;
  @override
  final uniqueFields = {'id'};
  @override
  final Map<String, RuntimeSqliteColumnDefinition> fieldsToSqliteColumns = {
    'primaryKey': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: '_brick_id',
      iterable: false,
      type: int,
    ),
    'id': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'id',
      iterable: false,
      type: String,
    ),
    'canalId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'canal_id',
      iterable: false,
      type: String,
    ),
    'usuarioId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'usuario_id',
      iterable: false,
      type: String,
    ),
    'cuerpo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'cuerpo',
      iterable: false,
      type: String,
    ),
    'createdAt': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'created_at',
      iterable: false,
      type: DateTime,
    ),
    'version': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'version',
      iterable: false,
      type: int,
    ),
  };
  @override
  Future<int?> primaryKeyByUniqueColumns(
    ChatMensaje instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'ChatMensaje';

  @override
  Future<ChatMensaje> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ChatMensajeFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    ChatMensaje input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ChatMensajeToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<ChatMensaje> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ChatMensajeFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    ChatMensaje input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ChatMensajeToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
