// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<ModuloEmpresa> _$ModuloEmpresaFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ModuloEmpresa(
    id: data['id'] as String,
    empresaId: data['empresa_id'] as String,
    moduloId: data['modulo_id'] as String,
    habilitado: data['habilitado'] as bool,
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$ModuloEmpresaToSupabase(
  ModuloEmpresa instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'modulo_id': instance.moduloId,
    'habilitado': instance.habilitado,
    'version': instance.version,
  };
}

Future<ModuloEmpresa> _$ModuloEmpresaFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ModuloEmpresa(
    id: data['id'] as String,
    empresaId: data['empresa_id'] as String,
    moduloId: data['modulo_id'] as String,
    habilitado: data['habilitado'] == 1,
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ModuloEmpresaToSqlite(
  ModuloEmpresa instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'modulo_id': instance.moduloId,
    'habilitado': instance.habilitado ? 1 : 0,
    'version': instance.version,
  };
}

/// Construct a [ModuloEmpresa]
class ModuloEmpresaAdapter
    extends OfflineFirstWithSupabaseAdapter<ModuloEmpresa> {
  ModuloEmpresaAdapter();

  @override
  final supabaseTableName = 'modulos_empresa';
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
    'moduloId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'modulo_id',
    ),
    'habilitado': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'habilitado',
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
    'empresaId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'empresa_id',
      iterable: false,
      type: String,
    ),
    'moduloId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'modulo_id',
      iterable: false,
      type: String,
    ),
    'habilitado': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'habilitado',
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
    ModuloEmpresa instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'ModuloEmpresa';

  @override
  Future<ModuloEmpresa> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ModuloEmpresaFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    ModuloEmpresa input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ModuloEmpresaToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<ModuloEmpresa> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ModuloEmpresaFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    ModuloEmpresa input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ModuloEmpresaToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
