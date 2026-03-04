// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<ChatterMensaje> _$ChatterMensajeFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ChatterMensaje(
    id: data['id'] as String,
    empresaId: data['empresa_id'] == null
        ? null
        : data['empresa_id'] as String?,
    entidadTipo: data['entidad_tipo'] as String,
    entidadId: data['entidad_id'] as String,
    tipo: data['tipo'] as String,
    subtype: data['subtype'] as String,
    esInterno: data['es_interno'] as bool,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    autorId: data['autor_id'] == null ? null : data['autor_id'] as String?,
    autorNombre: data['autor_nombre'] as String,
    autorAvatar: data['autor_avatar'] == null
        ? null
        : data['autor_avatar'] as String?,
    creadoEn: data['creado_en'] == null
        ? null
        : data['creado_en'] == null
        ? null
        : DateTime.tryParse(data['creado_en'] as String),
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$ChatterMensajeToSupabase(
  ChatterMensaje instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'entidad_tipo': instance.entidadTipo,
    'entidad_id': instance.entidadId,
    'tipo': instance.tipo,
    'subtype': instance.subtype,
    'es_interno': instance.esInterno,
    'cuerpo': instance.cuerpo,
    'autor_id': instance.autorId,
    'autor_nombre': instance.autorNombre,
    'autor_avatar': instance.autorAvatar,
    'creado_en': instance.creadoEn?.toIso8601String(),
    'version': instance.version,
  };
}

Future<ChatterMensaje> _$ChatterMensajeFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ChatterMensaje(
    id: data['id'] as String,
    entidadTipo: data['entidad_tipo'] as String,
    entidadId: data['entidad_id'] as String,
    tipo: data['tipo'] as String,
    subtype: data['subtype'] as String,
    esInterno: data['es_interno'] == 1,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    autorId: data['autor_id'] == null ? null : data['autor_id'] as String?,
    autorNombre: data['autor_nombre'] as String,
    autorAvatar: data['autor_avatar'] == null
        ? null
        : data['autor_avatar'] as String?,
    creadoEn: data['creado_en'] == null
        ? null
        : data['creado_en'] == null
        ? null
        : DateTime.tryParse(data['creado_en'] as String),
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ChatterMensajeToSqlite(
  ChatterMensaje instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'entidad_tipo': instance.entidadTipo,
    'entidad_id': instance.entidadId,
    'tipo': instance.tipo,
    'subtype': instance.subtype,
    'es_interno': instance.esInterno ? 1 : 0,
    'cuerpo': instance.cuerpo,
    'autor_id': instance.autorId,
    'autor_nombre': instance.autorNombre,
    'autor_avatar': instance.autorAvatar,
    'creado_en': instance.creadoEn?.toIso8601String(),
    'version': instance.version,
  };
}

/// Construct a [ChatterMensaje]
class ChatterMensajeAdapter
    extends OfflineFirstWithSupabaseAdapter<ChatterMensaje> {
  ChatterMensajeAdapter();

  @override
  final supabaseTableName = 'chatter_mensajes';
  @override
  final defaultToNull = true;
  @override
  final fieldsToSupabaseColumns = {
    'id': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'id',
    ),
    'empresaId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'empresa_id',
    ),
    'entidadTipo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'entidad_tipo',
    ),
    'entidadId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'entidad_id',
    ),
    'tipo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'tipo',
    ),
    'subtype': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'subtype',
    ),
    'esInterno': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'es_interno',
    ),
    'cuerpo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'cuerpo',
    ),
    'autorId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'autor_id',
    ),
    'autorNombre': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'autor_nombre',
    ),
    'autorAvatar': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'autor_avatar',
    ),
    'creadoEn': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'creado_en',
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
    'entidadTipo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'entidad_tipo',
      iterable: false,
      type: String,
    ),
    'entidadId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'entidad_id',
      iterable: false,
      type: String,
    ),
    'tipo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'tipo',
      iterable: false,
      type: String,
    ),
    'subtype': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'subtype',
      iterable: false,
      type: String,
    ),
    'esInterno': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'es_interno',
      iterable: false,
      type: bool,
    ),
    'cuerpo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'cuerpo',
      iterable: false,
      type: String,
    ),
    'autorId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'autor_id',
      iterable: false,
      type: String,
    ),
    'autorNombre': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'autor_nombre',
      iterable: false,
      type: String,
    ),
    'autorAvatar': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'autor_avatar',
      iterable: false,
      type: String,
    ),
    'creadoEn': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'creado_en',
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
    ChatterMensaje instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'ChatterMensaje';

  @override
  Future<ChatterMensaje> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ChatterMensajeFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    ChatterMensaje input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ChatterMensajeToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<ChatterMensaje> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ChatterMensajeFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    ChatterMensaje input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ChatterMensajeToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
