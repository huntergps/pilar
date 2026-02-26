// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<Modulo> _$ModuloFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Modulo(
    id: data['id'] as String,
    nombre: data['nombre'] as String,
    descripcion: data['descripcion'] == null
        ? null
        : data['descripcion'] as String?,
    tipo: data['tipo'] as String,
    icono: data['icono'] == null ? null : data['icono'] as String?,
    orden: data['orden'] == null ? null : data['orden'] as int?,
    activo: data['activo'] as bool,
  );
}

Future<Map<String, dynamic>> _$ModuloToSupabase(
  Modulo instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'nombre': instance.nombre,
    'descripcion': instance.descripcion,
    'tipo': instance.tipo,
    'icono': instance.icono,
    'orden': instance.orden,
    'activo': instance.activo,
  };
}

Future<Modulo> _$ModuloFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Modulo(
    id: data['id'] as String,
    nombre: data['nombre'] as String,
    descripcion: data['descripcion'] == null
        ? null
        : data['descripcion'] as String?,
    tipo: data['tipo'] as String,
    icono: data['icono'] == null ? null : data['icono'] as String?,
    orden: data['orden'] == null ? null : data['orden'] as int?,
    activo: data['activo'] == 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ModuloToSqlite(
  Modulo instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'nombre': instance.nombre,
    'descripcion': instance.descripcion,
    'tipo': instance.tipo,
    'icono': instance.icono,
    'orden': instance.orden,
    'activo': instance.activo ? 1 : 0,
  };
}

/// Construct a [Modulo]
class ModuloAdapter extends OfflineFirstWithSupabaseAdapter<Modulo> {
  ModuloAdapter();

  @override
  final supabaseTableName = 'modulos';
  @override
  final defaultToNull = true;
  @override
  final fieldsToSupabaseColumns = {
    'id': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'id',
    ),
    'nombre': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'nombre',
    ),
    'descripcion': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'descripcion',
    ),
    'tipo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'tipo',
    ),
    'icono': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'icono',
    ),
    'orden': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'orden',
    ),
    'activo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'activo',
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
    'tipo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'tipo',
      iterable: false,
      type: String,
    ),
    'icono': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'icono',
      iterable: false,
      type: String,
    ),
    'orden': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'orden',
      iterable: false,
      type: int,
    ),
    'activo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'activo',
      iterable: false,
      type: bool,
    ),
  };
  @override
  Future<int?> primaryKeyByUniqueColumns(
    Modulo instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'Modulo';

  @override
  Future<Modulo> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ModuloFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    Modulo input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ModuloToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Modulo> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ModuloFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    Modulo input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async =>
      await _$ModuloToSqlite(input, provider: provider, repository: repository);
}
