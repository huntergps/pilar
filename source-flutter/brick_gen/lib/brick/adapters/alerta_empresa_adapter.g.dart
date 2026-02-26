// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<AlertaEmpresa> _$AlertaEmpresaFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return AlertaEmpresa(
    id: data['id'] as String,
    empresaId: data['empresa_id'] as String,
    origenModulo: data['origen_modulo'] as String,
    codigoAlerta: data['codigo_alerta'] == null
        ? null
        : data['codigo_alerta'] as String?,
    severidad: data['severidad'] as String,
    titulo: data['titulo'] as String,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    accionUrl: data['accion_url'] == null
        ? null
        : data['accion_url'] as String?,
    estado: data['estado'] as String,
    createdAt: data['created_at'] == null
        ? null
        : data['created_at'] == null
        ? null
        : DateTime.tryParse(data['created_at'] as String),
  );
}

Future<Map<String, dynamic>> _$AlertaEmpresaToSupabase(
  AlertaEmpresa instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'origen_modulo': instance.origenModulo,
    'codigo_alerta': instance.codigoAlerta,
    'severidad': instance.severidad,
    'titulo': instance.titulo,
    'cuerpo': instance.cuerpo,
    'accion_url': instance.accionUrl,
    'estado': instance.estado,
    'created_at': instance.createdAt?.toIso8601String(),
  };
}

Future<AlertaEmpresa> _$AlertaEmpresaFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return AlertaEmpresa(
    id: data['id'] as String,
    empresaId: data['empresa_id'] as String,
    origenModulo: data['origen_modulo'] as String,
    codigoAlerta: data['codigo_alerta'] == null
        ? null
        : data['codigo_alerta'] as String?,
    severidad: data['severidad'] as String,
    titulo: data['titulo'] as String,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    accionUrl: data['accion_url'] == null
        ? null
        : data['accion_url'] as String?,
    estado: data['estado'] as String,
    createdAt: data['created_at'] == null
        ? null
        : data['created_at'] == null
        ? null
        : DateTime.tryParse(data['created_at'] as String),
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$AlertaEmpresaToSqlite(
  AlertaEmpresa instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'origen_modulo': instance.origenModulo,
    'codigo_alerta': instance.codigoAlerta,
    'severidad': instance.severidad,
    'titulo': instance.titulo,
    'cuerpo': instance.cuerpo,
    'accion_url': instance.accionUrl,
    'estado': instance.estado,
    'created_at': instance.createdAt?.toIso8601String(),
  };
}

/// Construct a [AlertaEmpresa]
class AlertaEmpresaAdapter
    extends OfflineFirstWithSupabaseAdapter<AlertaEmpresa> {
  AlertaEmpresaAdapter();

  @override
  final supabaseTableName = 'alertas_empresa';
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
    'origenModulo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'origen_modulo',
    ),
    'codigoAlerta': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'codigo_alerta',
    ),
    'severidad': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'severidad',
    ),
    'titulo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'titulo',
    ),
    'cuerpo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'cuerpo',
    ),
    'accionUrl': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'accion_url',
    ),
    'estado': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'estado',
    ),
    'createdAt': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'created_at',
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
    'origenModulo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'origen_modulo',
      iterable: false,
      type: String,
    ),
    'codigoAlerta': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'codigo_alerta',
      iterable: false,
      type: String,
    ),
    'severidad': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'severidad',
      iterable: false,
      type: String,
    ),
    'titulo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'titulo',
      iterable: false,
      type: String,
    ),
    'cuerpo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'cuerpo',
      iterable: false,
      type: String,
    ),
    'accionUrl': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'accion_url',
      iterable: false,
      type: String,
    ),
    'estado': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'estado',
      iterable: false,
      type: String,
    ),
    'createdAt': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'created_at',
      iterable: false,
      type: DateTime,
    ),
  };
  @override
  Future<int?> primaryKeyByUniqueColumns(
    AlertaEmpresa instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'AlertaEmpresa';

  @override
  Future<AlertaEmpresa> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$AlertaEmpresaFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    AlertaEmpresa input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$AlertaEmpresaToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<AlertaEmpresa> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$AlertaEmpresaFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    AlertaEmpresa input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$AlertaEmpresaToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
