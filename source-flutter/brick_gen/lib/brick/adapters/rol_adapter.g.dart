// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<Rol> _$RolFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Rol(
    id: data['id'] as String,
    empresaId: data['empresa_id'] == null
        ? null
        : data['empresa_id'] as String?,
    codigo: data['codigo'] as String,
    nombre: data['nombre'] as String,
    descripcion: data['descripcion'] == null
        ? null
        : data['descripcion'] as String?,
    esSistema: data['es_sistema'] as bool,
    activo: data['activo'] as bool,
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$RolToSupabase(
  Rol instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'codigo': instance.codigo,
    'nombre': instance.nombre,
    'descripcion': instance.descripcion,
    'es_sistema': instance.esSistema,
    'activo': instance.activo,
    'version': instance.version,
  };
}

Future<Rol> _$RolFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Rol(
    id: data['id'] as String,
    codigo: data['codigo'] as String,
    nombre: data['nombre'] as String,
    descripcion: data['descripcion'] == null
        ? null
        : data['descripcion'] as String?,
    esSistema: data['es_sistema'] == 1,
    activo: data['activo'] == 1,
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$RolToSqlite(
  Rol instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'codigo': instance.codigo,
    'nombre': instance.nombre,
    'descripcion': instance.descripcion,
    'es_sistema': instance.esSistema ? 1 : 0,
    'activo': instance.activo ? 1 : 0,
    'version': instance.version,
  };
}

/// Construct a [Rol]
class RolAdapter extends OfflineFirstWithSupabaseAdapter<Rol> {
  RolAdapter();

  @override
  final supabaseTableName = 'roles';
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
    'codigo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'codigo',
    ),
    'nombre': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'nombre',
    ),
    'descripcion': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'descripcion',
    ),
    'esSistema': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'es_sistema',
    ),
    'activo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'activo',
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
    'codigo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'codigo',
      iterable: false,
      type: String,
    ),
    'nombre': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'nombre',
      iterable: false,
      type: String,
    ),
    'descripcion': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'descripcion',
      iterable: false,
      type: String,
    ),
    'esSistema': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'es_sistema',
      iterable: false,
      type: bool,
    ),
    'activo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'activo',
      iterable: false,
      type: bool,
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
    Rol instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'Rol';

  @override
  Future<Rol> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$RolFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    Rol input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async =>
      await _$RolToSupabase(input, provider: provider, repository: repository);
  @override
  Future<Rol> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async =>
      await _$RolFromSqlite(input, provider: provider, repository: repository);
  @override
  Future<Map<String, dynamic>> toSqlite(
    Rol input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async =>
      await _$RolToSqlite(input, provider: provider, repository: repository);
}
