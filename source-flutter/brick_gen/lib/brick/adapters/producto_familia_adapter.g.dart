// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<ProductoFamilia> _$ProductoFamiliaFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ProductoFamilia(
    id: data['id'] as String,
    empresaId: data['empresa_id'] == null ? null : data['empresa_id'] as String?,
    nombre: data['nombre'] as String,
    descripcion: data['descripcion'] == null ? null : data['descripcion'] as String?,
    imagenUrl: data['imagen_url'] == null ? null : data['imagen_url'] as String?,
    categoriaId: data['categoria_id'] == null ? null : data['categoria_id'] as String?,
    activo: data['activo'] as bool,
  );
}

Future<Map<String, dynamic>> _$ProductoFamiliaToSupabase(
  ProductoFamilia instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'nombre': instance.nombre,
    'descripcion': instance.descripcion,
    'imagen_url': instance.imagenUrl,
    'categoria_id': instance.categoriaId,
    'activo': instance.activo,
  };
}

Future<ProductoFamilia> _$ProductoFamiliaFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ProductoFamilia(
    id: data['id'] as String,
    nombre: data['nombre'] as String,
    descripcion: data['descripcion'] == null ? null : data['descripcion'] as String?,
    activo: data['activo'] == 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ProductoFamiliaToSqlite(
  ProductoFamilia instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'nombre': instance.nombre,
    'descripcion': instance.descripcion,
    'activo': instance.activo ? 1 : 0,
  };
}

/// Construct a [ProductoFamilia]
class ProductoFamiliaAdapter extends OfflineFirstWithSupabaseAdapter<ProductoFamilia> {
  ProductoFamiliaAdapter();

  @override
  final supabaseTableName = 'producto_familias';
  @override
  final defaultToNull = true;
  @override
  final fieldsToSupabaseColumns = {
    'id': const RuntimeSupabaseColumnDefinition(association: false, columnName: 'id'),
    'empresaId': const RuntimeSupabaseColumnDefinition(association: false, columnName: 'empresa_id'),
    'nombre': const RuntimeSupabaseColumnDefinition(association: false, columnName: 'nombre'),
    'descripcion': const RuntimeSupabaseColumnDefinition(association: false, columnName: 'descripcion'),
    'imagenUrl': const RuntimeSupabaseColumnDefinition(association: false, columnName: 'imagen_url'),
    'categoriaId': const RuntimeSupabaseColumnDefinition(association: false, columnName: 'categoria_id'),
    'activo': const RuntimeSupabaseColumnDefinition(association: false, columnName: 'activo'),
  };
  @override
  final ignoreDuplicates = false;
  @override
  final uniqueFields = {'id'};
  @override
  final Map<String, RuntimeSqliteColumnDefinition> fieldsToSqliteColumns = {
    'primaryKey': const RuntimeSqliteColumnDefinition(
      association: false, columnName: '_brick_id', iterable: false, type: int,
    ),
    'id': const RuntimeSqliteColumnDefinition(
      association: false, columnName: 'id', iterable: false, type: String,
    ),
    'nombre': const RuntimeSqliteColumnDefinition(
      association: false, columnName: 'nombre', iterable: false, type: String,
    ),
    'descripcion': const RuntimeSqliteColumnDefinition(
      association: false, columnName: 'descripcion', iterable: false, type: String,
    ),
    'activo': const RuntimeSqliteColumnDefinition(
      association: false, columnName: 'activo', iterable: false, type: bool,
    ),
  };
  @override
  Future<int?> primaryKeyByUniqueColumns(
    ProductoFamilia instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'ProductoFamilia';

  @override
  Future<ProductoFamilia> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProductoFamiliaFromSupabase(input, provider: provider, repository: repository);
  @override
  Future<Map<String, dynamic>> toSupabase(
    ProductoFamilia input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProductoFamiliaToSupabase(input, provider: provider, repository: repository);
  @override
  Future<ProductoFamilia> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProductoFamiliaFromSqlite(input, provider: provider, repository: repository);
  @override
  Future<Map<String, dynamic>> toSqlite(
    ProductoFamilia input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProductoFamiliaToSqlite(input, provider: provider, repository: repository);
}
