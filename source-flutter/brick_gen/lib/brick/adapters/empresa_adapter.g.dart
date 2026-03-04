// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<Empresa> _$EmpresaFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Empresa(
    id: data['id'] as String,
    nombre: data['nombre'] as String,
    nombreComercial: data['nombre_comercial'] == null
        ? null
        : data['nombre_comercial'] as String?,
    ruc: data['ruc'] == null ? null : data['ruc'] as String?,
    logoUrl: data['logo_url'] == null ? null : data['logo_url'] as String?,
    colorPrimario: data['color_primario'] == null
        ? null
        : data['color_primario'] as String?,
    colorSecundario: data['color_secundario'] == null
        ? null
        : data['color_secundario'] as String?,
    estado: data['estado'] == null ? null : data['estado'] as String?,
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$EmpresaToSupabase(
  Empresa instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'nombre': instance.nombre,
    'nombre_comercial': instance.nombreComercial,
    'ruc': instance.ruc,
    'logo_url': instance.logoUrl,
    'color_primario': instance.colorPrimario,
    'color_secundario': instance.colorSecundario,
    'estado': instance.estado,
    'version': instance.version,
  };
}

Future<Empresa> _$EmpresaFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Empresa(
    id: data['id'] as String,
    nombre: data['nombre'] as String,
    nombreComercial: data['nombre_comercial'] == null
        ? null
        : data['nombre_comercial'] as String?,
    ruc: data['ruc'] == null ? null : data['ruc'] as String?,
    logoUrl: data['logo_url'] == null ? null : data['logo_url'] as String?,
    colorPrimario: data['color_primario'] == null
        ? null
        : data['color_primario'] as String?,
    colorSecundario: data['color_secundario'] == null
        ? null
        : data['color_secundario'] as String?,
    estado: data['estado'] == null ? null : data['estado'] as String?,
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$EmpresaToSqlite(
  Empresa instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'nombre': instance.nombre,
    'nombre_comercial': instance.nombreComercial,
    'ruc': instance.ruc,
    'logo_url': instance.logoUrl,
    'color_primario': instance.colorPrimario,
    'color_secundario': instance.colorSecundario,
    'estado': instance.estado,
    'version': instance.version,
  };
}

/// Construct a [Empresa]
class EmpresaAdapter extends OfflineFirstWithSupabaseAdapter<Empresa> {
  EmpresaAdapter();

  @override
  final supabaseTableName = 'empresas';
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
    'nombreComercial': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'nombre_comercial',
    ),
    'ruc': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'ruc',
    ),
    'logoUrl': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'logo_url',
    ),
    'colorPrimario': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'color_primario',
    ),
    'colorSecundario': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'color_secundario',
    ),
    'estado': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'estado',
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
    'nombre': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'nombre',
      iterable: false,
      type: String,
    ),
    'nombreComercial': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'nombre_comercial',
      iterable: false,
      type: String,
    ),
    'ruc': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'ruc',
      iterable: false,
      type: String,
    ),
    'logoUrl': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'logo_url',
      iterable: false,
      type: String,
    ),
    'colorPrimario': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'color_primario',
      iterable: false,
      type: String,
    ),
    'colorSecundario': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'color_secundario',
      iterable: false,
      type: String,
    ),
    'estado': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'estado',
      iterable: false,
      type: String,
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
    Empresa instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'Empresa';

  @override
  Future<Empresa> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$EmpresaFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    Empresa input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$EmpresaToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Empresa> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$EmpresaFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    Empresa input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$EmpresaToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
