// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<Producto> _$ProductoFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Producto(
    id: data['id'] as String,
    empresaId: data['empresa_id'] == null
        ? null
        : data['empresa_id'] as String?,
    codigo: data['codigo'] == null ? null : data['codigo'] as String?,
    nombre: data['nombre'] as String,
    tipo: data['tipo'] as String,
    precioVenta: data['precio_venta'] == null
        ? null
        : data['precio_venta'] as String?,
    precioCosto: data['precio_costo'] == null
        ? null
        : data['precio_costo'] as String?,
    descripcion: data['descripcion'] == null
        ? null
        : data['descripcion'] as String?,
    codigoPrincipalBarras: data['codigo_principal_barras'] == null
        ? null
        : data['codigo_principal_barras'] as String?,
    unidadMedidaId: data['unidad_medida_id'] == null
        ? null
        : data['unidad_medida_id'] as String?,
    familiaId: data['familia_id'] == null
        ? null
        : data['familia_id'] as String?,
    categoriaId: data['categoria_id'] == null
        ? null
        : data['categoria_id'] as String?,
    activo: data['activo'] as bool,
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$ProductoToSupabase(
  Producto instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'codigo': instance.codigo,
    'nombre': instance.nombre,
    'tipo': instance.tipo,
    'precio_venta': instance.precioVenta,
    'precio_costo': instance.precioCosto,
    'descripcion': instance.descripcion,
    'codigo_principal_barras': instance.codigoPrincipalBarras,
    'unidad_medida_id': instance.unidadMedidaId,
    'familia_id': instance.familiaId,
    'categoria_id': instance.categoriaId,
    'activo': instance.activo,
    'version': instance.version,
  };
}

Future<Producto> _$ProductoFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Producto(
    id: data['id'] as String,
    codigo: data['codigo'] == null ? null : data['codigo'] as String?,
    nombre: data['nombre'] as String,
    tipo: data['tipo'] as String,
    precioVenta: data['precio_venta'] == null
        ? null
        : data['precio_venta'] as String?,
    precioCosto: data['precio_costo'] == null
        ? null
        : data['precio_costo'] as String?,
    descripcion: data['descripcion'] == null
        ? null
        : data['descripcion'] as String?,
    codigoPrincipalBarras: data['codigo_principal_barras'] == null
        ? null
        : data['codigo_principal_barras'] as String?,
    activo: data['activo'] == 1,
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ProductoToSqlite(
  Producto instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'codigo': instance.codigo,
    'nombre': instance.nombre,
    'tipo': instance.tipo,
    'precio_venta': instance.precioVenta,
    'precio_costo': instance.precioCosto,
    'descripcion': instance.descripcion,
    'codigo_principal_barras': instance.codigoPrincipalBarras,
    'activo': instance.activo ? 1 : 0,
    'version': instance.version,
  };
}

/// Construct a [Producto]
class ProductoAdapter extends OfflineFirstWithSupabaseAdapter<Producto> {
  ProductoAdapter();

  @override
  final supabaseTableName = 'productos';
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
    'tipo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'tipo',
    ),
    'precioVenta': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'precio_venta',
    ),
    'precioCosto': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'precio_costo',
    ),
    'descripcion': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'descripcion',
    ),
    'codigoPrincipalBarras': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'codigo_principal_barras',
    ),
    'unidadMedidaId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'unidad_medida_id',
    ),
    'familiaId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'familia_id',
    ),
    'categoriaId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'categoria_id',
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
    'tipo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'tipo',
      iterable: false,
      type: String,
    ),
    'precioVenta': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'precio_venta',
      iterable: false,
      type: String,
    ),
    'precioCosto': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'precio_costo',
      iterable: false,
      type: String,
    ),
    'descripcion': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'descripcion',
      iterable: false,
      type: String,
    ),
    'codigoPrincipalBarras': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'codigo_principal_barras',
      iterable: false,
      type: String,
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
    Producto instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'Producto';

  @override
  Future<Producto> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProductoFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    Producto input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProductoToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Producto> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProductoFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    Producto input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProductoToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
